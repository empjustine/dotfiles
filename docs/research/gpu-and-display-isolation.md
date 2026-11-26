---
id: research-gpu-display-isolation
type: architecture-design
status: draft
title: "Isolating accelerated workloads, and showing their surfaces"
parent: index
references: [index, research-workload-isolation-egress, research-workload-provisioning, research-multi-uid-access, research-quadronegro-design, research-quadronegro-availability-threats, declarative-upkeep-poc, system, decision-log]
---

# Isolating accelerated workloads, and showing their surfaces

This note covers the two workloads the container model does not describe well:
one that needs the GPU for compute (the `llama-swap`/`llama.cpp` server in
`~/agentcontainer`), and ones that need the GPU plus a display, input and audio
(games, browsers). It records where the real security boundary sits for each,
what is left to improve on a single-GPU desktop, and why Linux has no
SurfaceFlinger-equivalent that would let one user's session display another
user's surfaces.

The companion documents are [workload isolation and
egress](workload-isolation-and-egress.md) for the uid/slice/netns frame,
[workload provisioning](workload-provisioning.md) for turning these into
declarations, and [multi-uid access](multi-uid-data-access.md) for the data
side. The hardware facts are from the `~/agentcontainer` notes
(`docs/container-tooling.md`, `docs/d020-libvirt-qemu-sandbox.md`) and the
runner (`llm-local-inference/run.py`).

## The boundary is the driver, not the container

For an accelerated workload, "isolation" has three layers, and only the first
two are container properties:

| layer | what it decides | who enforces it |
| --- | --- | --- |
| device access | which device nodes exist in the container | cgroup device controller, `--device`, render-group membership |
| process sandbox | seccomp, capabilities, mount view, userns | podman/runc, SELinux |
| **GPU driver** | what an ioctl can make the kernel driver do to the GPU, other clients' VRAM, and the display | `amdgpu`/`nvidia` kernel driver |

The third layer is the one that matters and the one a container cannot improve.
On a consumer RDNA2 card (gfx1030) there is no SR-IOV, no MIG and no mediated
device, so two processes always share one GPU through one driver; isolation
between them is driver quality, not a kernel boundary. `HIP_VISIBLE_DEVICES` /
`ROCR_VISIBLE_DEVICES` and Vulkan device selection are *enumeration* filters a
cooperating process obeys — not a security control.

## Current state, and what is left

The `llm-local-inference` runner already does the container half correctly:
`--userns=keep-id --group-add keep-groups` (rootless, so the render group comes
from the host identity), `--device` for `/dev/dri/renderD*` and `/dev/kfd`,
`--read-only --tmpfs /tmp`, `--cap-drop ALL`, `--security-opt
no-new-privileges`, `--user <uid>:<gid>`, the HF cache mounted read-only, and a
published port. The remaining levers are small but real:

1. **Drop `/dev/kfd` unless the backend needs ROCm.** The image is
   `unified-vulkan`; Vulkan needs the render node only, while `/dev/kfd`
   exposes the AMD compute/HFI interface — a wider ioctl surface for no
   benefit. Pass it only for a HIP/ROCm backend.
2. **Never pass `/dev/dri/card*`.** A primary node carries KMS/DRI-master
   ioctls: the holder can become DRM master, own the outputs and read the host
   compositor's framebuffers. Render nodes (`renderD*`) cannot.
3. **Bind the listener, don't publish it to the world.** The runner publishes
   `9292` on the LAN; a `--network=host`-free deployment can bind
   `PublishPort=127.0.0.1:9292:8080` or a VLAN address and let the firewall
   decide who reaches it, instead of binding `0.0.0.0` inside the container.
4. **Move the API key out of the environment.** `TLALACAYOTL_API_KEY` is passed
   as an env var, which root can read from `/proc/<pid>/environ`; a
   `LoadCredentialEncrypted=` plus `--env-file` from the credential directory
   removes it from the process table's view.
5. **Give it a slice, not the machine.** `CPUWeight`/`AllowedCPUs` reserve
   host cores, `IOWeight` keeps model reads from starving the pool, and
   `MemoryHigh` (not `MemoryMax`) lets the GGUF page cache be reclaimed instead
   of OOM-killing the server. `LimitMEMLOCK=infinity` only if `--mlock` is used.
6. **Cap VRAM explicitly.** There is no VRAM cgroup on `amdgpu`: `-c`/`--n-gpu-layers`
   and llama-swap's `ttl` are the only limits, and an inference server that
   allocates the whole 16 GB will OOM the desktop compositor and any game.

## Boundaries that actually exist

In descending order of strength, with the cost:

| shape | boundary | cost on this host |
| --- | --- | --- |
| **separate GPU per trust domain** (iGPU for display, dGPU for compute) | the compute workload never touches the display path's driver instance | one more device; the dGPU stops driving the desktop |
| **VFIO passthrough to a VM** | kernel boundary; the guest owns the device and the host driver never sees the guest's ioctls | the host loses the GPU while the VM runs; Navi21 reset quirks; a second GPU makes this the cheapest *real* boundary |
| **virtio-gpu / Venus in a VM** | guest userspace isolated; rendering shares the host driver | rendering only — ROCm/HIP does not work through it, so not for `llama.cpp` |
| **container with render node** | process sandbox; same driver trust domain as the host | free, and the right tier for first-party workloads |
| **"device selection" env vars** | cooperation, not enforcement | none — not a boundary |

That ordering matches the `~/agentcontainer` decision (d020): keep local GGUF
serving in the host container on a single gfx1030, and revisit only with a
second, VFIO-dedicated GPU. What a container *does* buy is bounded damage from
everything except the driver: no host filesystem, no capabilities, no network
beyond its port, and an OOM/`TasksMax` ceiling.

## One GPU, two clients: compute and display

When the same card drives the desktop and the inference server, two failures
appear that no uid split prevents:

- **VRAM contention**: the compositor's buffers are resident; an inference
  server that takes the card's remaining memory evicts them. This is why the
  VRAM cap above is an isolation measure, not a tuning knob.
- **Time contention**: `amdgpu` has no MPS-style time slicing for consumer
  cards, so a saturated compute queue delays the compositor and every game.
  The only policy is mutual exclusion: a `gaming` target and a `compute` target
  that cannot be active together (`Conflicts=`), or llama-swap's own idle
  unload (`ttl`) with a short `-c`.

That is the same shape as the pool's two state targets: the resource is
singular, so the states are exclusive and the exclusivity is declared, not
hoped for.

There is no iGPU on this machine, so the desktop and any compute job share one
card unless a second one is added. That third failure mode is the one that
justifies the hardware: **a GPU hang is not demotable**. One bad command stream
can trip a ring timeout and force an `amdgpu` reset, which kills every context
on the card — the compositor included. VRAM caps do not help there, and no
cgroup exists for GPU time. A second card makes compute DoS-insulated from the
desktop, which is worth more than the extra VRAM.

## Two cards: what it buys and how to wire it

The optimistic shape the owner described — a larger card dedicated to compute,
the current gfx1030 still serving display plus a small compute share — is the
right one, with four conditions:

1. **The display card stays the primary/boot GPU.** Set it in firmware (or
   `video=`/EFI primary), keep the compute card headless. Swapping them later
   is a firmware trip, not a config change.
2. **Identify cards by PCI path, not by node number.** `renderD128`/`renderD129`
   are allocated in probe order and can change after a driver update or a slot
   swap; `/dev/dri/by-path/pci-0000:0X:00.0-render` is stable, which is what
   `--device` should name.
3. **Pin the client, not the machine.** Vulkan: `VK_ICD_FILENAMES` plus
   `DRI_PRIME`/`MESA_VK_DEVICE_SELECT`; ROCm: `HIP_VISIBLE_DEVICES` /
   `ROCR_VISIBLE_DEVICES`; containers: pass only the chosen by-path node, so a
   bug in the workload cannot enumerate the other card at all.
4. **Keep the display card's share small and capped** — small models or
   embeddings only, with an explicit `-c`/`--n-gpu-layers` ceiling and an
   admission check against free VRAM before start (`rocm-smi --showmeminfo vram`
   is enough for a refusal), because there is still no VRAM cgroup.

What it does *not* buy: a security boundary between the two compute workloads.
Both still talk to an `amdgpu` instance; only VFIO of the whole card (which
takes it away from the host) or a per-card trust split does that.

## Detaching and demoting a session without ending it

"tmux detach" for a graphical session has three distinct meanings, and they
have different mechanisms:

| want | mechanism | what it costs | reversible |
| --- | --- | --- | --- |
| stop **scanout**, keep every process | switch VT (`chvt`, `loginctl activate <other>`) | compositor loses DRM master and pauses; clients throttle on frame callbacks | `chvt` back, or a stream client |
| stop **composition** entirely | `SIGSTOP` the compositor (`kill -STOP $(pidof …)`) | desktop frozen on its VT; clients block on the Wayland socket | `SIGCONT` |
| keep it **running but secondary** | `systemctl set-property session-N.scope CPUWeight=1 IOWeight=1`; `Nice=19`; a frame cap where the compositor has one (`gamescope -r`) | it stays visible and keeps some GPU time | `systemctl set-property` back |

The VT switch is the actual "detach": the kernel takes DRM master away when
another VT becomes active, the compositor gets the logind pause signal, stops
presenting, and the graphical clients fall back to near-idle because nothing
asks them for frames. Buffers stay allocated (VRAM is not freed), so it is a
*compute-time* detach, not a memory one. `SIGSTOP` goes further but freezes
input too — do it only while the session is not the active VT, or the desktop
becomes unrecoverable from its own keyboard.

For workloads that must be detachable *by design*, do not give them the
physical display at all: run the session on a headless compositor (`sway
--headless`, `cage`, a virtual output) and attach a stream client (Sunshine,
`wayvnc`, PipeWire capture). Then "detach" is closing the stream, nothing is
frozen, VRAM is released when the session's clients exit, and the display card
never enters the picture.

Two things are *not* demotable and must be handled by policy instead: a GPU
hang (only a card reset, which is why the second card matters) and kernel-mode
anti-cheat (it will not run under any of these).

## Games and browsers

These need display, input and audio, which changes the unit of isolation from
"a container" to "a session":

| shape | how it looks | isolation | notes |
| --- | --- | --- | --- |
| **separate user session** (own VT, own compositor, `loginctl` seat) | a second desktop on another TTY; switch with `ctrl-alt-fn` | DAC between users, shared kernel | the simplest real split; input/audio devices belong to the seat |
| **nested compositor in a container** (`gamescope`/`cage` inside bwrap/podman) | a window in the host session | process sandbox, same session | Steam Deck's shape; GPU + Wayland socket + PipeWire sockets passed in; fragile with userns and socket ownership |
| **VM with GPU passthrough + Looking Glass** | a window showing the guest's framebuffer | kernel boundary | the strongest; the host loses the GPU; anti-cheat treats it as a VM |
| **Flatpak/bwrap** | host session | filesystem/portal confinement | the mainstream answer for games; not a uid boundary |

- **Input and audio** decide most of the feasibility: `/dev/input/event*`
  (needs the `input` group, or a portal), PipeWire/Pulse sockets in
  `$XDG_RUNTIME_DIR` (per-user, mode 0700), and udev rules for controllers.
  A second user cannot reach the first user's PipeWire socket; it gets its own
  session bus and its own audio server instance.
- **Browsers** are the easy case: they already carry their own sandbox
  (seccomp + userns + the zygote), so the useful isolation is a separate uid,
  a separate `--user-data-dir`, no write access to the pool beyond a download
  directory, and no GPU access if hardware video decode is not required.
- **Anti-cheat** is the hard limit: kernel-mode anti-cheat does not run inside a
  container and treats a VM as a VM. That is a product constraint, not an
  isolation one.

## Why there is no SurfaceFlinger

Android's SurfaceFlinger is a system service that owns the display and
composites buffers handed to it by apps. Linux splits that role three ways, and
the split is deliberate:

1. **KMS/DRM** owns the outputs; whoever holds the DRM *master* on a card owns
   the connectors. One master per card (CRTC) at a time; `drm_lease` can hand a
   connector to another process, but only within one master's session.
2. **logind seats** arbitrate *who* gets the devices: a seat is a set of GPU,
   input and sound devices with exactly one active session. `loginctl
   seat-status` shows it; `loginctl attach` builds multi-seat; `seatd` is the
   light alternative for compositors that do not use logind.
3. **The compositor is the display server** — per session, per user. There is
   no cross-user surface aggregator, because that would be a global
   screen-read/input-inject capability, which is exactly what a display server
   without a security model has (X11).

So the question "how do I display another user's workload" has four real
answers, none of them a SurfaceFlinger:

- **Nested compositor as a window**: the workload's compositor runs as a client
  of the host's. Simple, but either the workload runs as the host user (no uid
  split) or it is given the host's Wayland socket — and sharing a Wayland
  socket is *narrower* than sharing X11 (a client draws only its own surface
  and gets input only when focused) but still not a boundary worth crossing for
  an untrusted workload.
- **Headless compositor plus capture/stream**: the workload's session runs on a
  virtual output and is streamed (PipeWire capture + Sunshine/Moonlight,
  `wayvnc`, or a portal-driven share). This is the practical shape for games
  when the workload must stay in its own session: full uid isolation, and the
  "surface" is a video stream.
- **VM plus Looking Glass**: the guest composites its own desktop; the host
  shows the framebuffer through shared memory. The closest thing to
  SurfaceFlinger's "surface from another domain", and the only one that is a
  kernel boundary.
- **Just switch seats/sessions**: two users, two VTs, one GPU. It is the
  cheapest real split and the one that keeps every device where it belongs.

The X11 warning is worth stating plainly: a shared X display is a
keylogger/screenshot/input-injection capability for any client. Xwayland does
not change that; it is per-session for the same reason.

## What to build for this host

1. With one card: a `compute` / `gaming` pair of mutually exclusive targets
   (`Conflicts=`), plus `ttl` on llama-swap so an idle model releases VRAM. With
   a second card: drop the exclusivity for GPU reasons and keep it only for
   CPU/IO, plus a VRAM admission check on the display card's small share.
2. Stable card identity: `--device /dev/dri/by-path/…`, `ROCR_VISIBLE_DEVICES`/
   `VK_ICD_FILENAMES` per workload, display card primary in firmware.
2. The inference unit as a slice with `CPUWeight`, `IOWeight`, `MemoryHigh` and
   an explicit VRAM cap, instead of "the whole machine".
3. `renderD*` only (plus `/dev/kfd` only when a ROCm backend exists), never a
   `card*` node, never `--privileged`.
4. For the graphical workloads: separate users with their own seats/VTs, and
   the streaming shape only if a session has to be visible inside another one.
5. When a real boundary is needed: a second GPU dedicated to VFIO, not a
   cleverer container.

## Open questions

- Is there an iGPU on this machine that could take over the desktop, freeing
  the dGPU for compute (and for VFIO later)?
- Does any workload actually need a *displayed* surface from another user, or
  is a streamed/remote view enough (which removes the whole compositor-sharing
  question)?
- Whether games should live in a separate seat or a VM on this hardware, given
  anti-cheat behaviour.
- Whether the inference server should keep publishing on the LAN at all, or
  bind loopback and be reached through the existing tunnel/reverse-proxy.

## Non-goals

- No claim that a container isolates the GPU driver; it does not.
- No VM, VFIO binding, compositor or streaming stack is installed by this note.
- No claim about a specific game's anti-cheat behaviour beyond "kernel
  anti-cheat and VMs are a known incompatibility".
