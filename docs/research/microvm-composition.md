---
id: research-microvm-composition
type: architecture-design
status: draft
title: "VMs and microVMs: composability, nesting and distribution"
parent: index
references: [index, research-storage-overlay, research-workload-isolation-egress, research-multi-uid-access, research-files-volumes, research-quadronegro-availability-threats, research-gpu-display-isolation, decision-log]
---

# VMs and microVMs: composability, nesting and distribution

The [storage note](storage-overlay.md) ends with an open question — is host
root inside the threat model? Containers answer "yes, it is": a FUSE daemon or
a bind mount on the host sees plaintext. This note asks whether a VM or
microVM layer changes that, what it costs, how it composes with systemd and
with k3s/k0s, whether nesting adds anything, and what distribution over more
machines does to security.

Claims about the VMMs are read from the vendored trees (Firecracker, Cloud
Hypervisor, libkrun, Kata, Kuasar, microvm.nix, Keylime), the sandbox projects
(Gondolin, smolvm, crun and crun-vm), the kernel's nested KVM documentation,
and the earlier notes in this tree. Nothing was run.

## The boundary is orthogonal to the storage core

A VM does not change the object format, the key hierarchy or the placement
policy. It changes two things: **which device carries the bytes** and **which
process holds the key**. That is why the two designs compose at all.

| rung | container interface | VM interface | who holds the key |
| --- | --- | --- | --- |
| git | network to a forge | virtio-net | the forge or the client |
| object | S3 over the host network | virtio-net, or vsock to a proxy | the workload, if the client runs in the guest |
| files | bind mount or host FUSE | virtio-fs, or a FUSE client *inside* the guest | the host (virtio-fs) or the guest (client in guest) |
| block | `/dev/mapper/*` bind | virtio-blk of a LUKS'd LV | the guest, if it unlocks the LUKS device |

The rung table is the composability answer: every rung has a VM device, and
the only rung whose interface *forces* host-side plaintext is `files` through a
shared directory.

## Where the plaintext lives

This is the decisive difference between a VM that is genuinely a trust boundary
and one that is a boundary-shaped deployment.

| interface | host sees plaintext | guest sees plaintext | notes |
| --- | --- | --- | --- |
| bind mount / host FUSE | yes | yes | the container model; the host is trusted by construction |
| virtio-fs | yes — virtiofsd serves the decrypted tree | yes | the export path is not a sandbox; narrow it and quota it |
| 9p | yes | yes | weaker model than virtio-fs; avoid for untrusted guests |
| NFS | yes — the server decrypts | yes | `sec=krb5p` authenticates the client, it does not hide content from the server |
| virtio-blk + LUKS in the guest | no — ciphertext blocks | yes | strong against the host; loses object-level FEC and partial recovery |
| object API with the client in the guest | no | yes | the only interface that keeps R1/R2 intact across the boundary |

The consequence is worth stating plainly: **a shared directory and
"the host must not read the data" are mutually exclusive.** If the host must be
outside the confidentiality boundary, the guest has to run the object client —
and therefore the FUSE mount too — with a key the host never holds. That is a
bigger change than "put the workload in a VM", and it is the point where the
VM design and the storage design actually meet.

libkrun's own security model says the quiet part out loud: the VM boundary does
not restrict host resources exposed through devices, the VMM handles guest
requests with its host permissions, and the virtio-fs export path must not be
treated as a sandbox. A device model is a capability grant, not a wall.

## Overhead

| VMM | device model | density and boot | virtio-fs | confidential guests | notes |
| --- | --- | --- | --- | --- | --- |
| Firecracker | block, net, vsock, serial; no PCI, no GPU | VMM threads ≤ 5 MiB, 5 microVMs per core-second at 128 MiB guest RAM | no | no SEV-SNP/TDX | the smallest surface; a container image must arrive as a block device |
| Cloud Hypervisor | virtio block/net/fs, hotplug, VFIO, vhost-user | low footprint; a full Rust VMM | yes, with DAX | SEV-SNP (no memory/CPU hotplug, no hugepages, no vIOMMU, no vDPA) | the practical middle: virtio-fs and passthrough when needed |
| libkrun | virtio console/block/fs/net/vsock/balloon/gpu | a library inside the runtime, no separate VMM process | yes | SEV and TDX variants | the cheapest way to keep Podman: `crun` runs the workload under `--runtime=krun` |
| Kata Containers | VM per pod, QEMU/Cloud Hypervisor/Firecracker backends | container-shaped lifecycle, VM-shaped isolation | backend-dependent | CoCo configs (`kata-qemu-coco`) | the Kubernetes answer; a containerd shim and a RuntimeClass |
| QEMU (full) | everything | largest memory and surface | yes | SEV/SNP/TDX with configuration | the compatibility choice, not the minimal one |
| systemd-nspawn | none — namespace container | container | n/a | no | not a VM boundary |

Three rules follow.

- **The smallest device model that carries the needed interface.** For an
  object-only workload that is virtio-net plus vsock; for `files` it is
  virtio-fs; block and GPU are exceptions.
- **Per-VM kernel means per-VM patching.** Density is not only RAM: every guest
  kernel is a patch target, and every VM boot is a page-cache cold start.
- **Confidential guests change the arithmetic.** They put the host outside the
  guest's TCB, which is the only way to answer the storage note's open question
  without a second machine — at the cost of the SNP limitations above.

## Sandbox projects: Gondolin, smolvm and krun

Three projects turn "microVM for untrusted work" into a product. They share a
premise that is the *opposite* of the storage note's open question: the host is
trusted and the guest is adversarial. That makes them excellent prior art for
workload isolation and poor fits for "host root is outside the model".

### What each one is

| project | shape | boundary | mediation | state |
| --- | --- | --- | --- | --- |
| **Gondolin** (earendil-works) | TypeScript SDK + CLI, Rust daemon `gondolind`, guest Alpine, libkrun default and QEMU fallback | hardware microVM, guest treated as adversarial | userspace netstack: allowlist, internal-range blocking, DNS modes, HTTP/1.1 TLS interception, SSH egress proxy, mapped TCP; placeholder secrets substituted by the host per allowed host; programmable VFS (FUSE over virtio-serial, or virtio-fs) | disk-only qcow2 checkpoints (no RAM); remote daemon over SSH |
| **smolvm** (smol-machines) | CLI + Node/Python/Rust/Go SDKs, bundled libkrun, OCI images, local and cloud transports | hardware microVM per workload; the `smol-vmm` helper is confined by seccomp and Landlock on Linux | networking **off by default**, `allow_hosts`, a mediated-egress decider (allow/deny/redirect, no TLS inspection), credential substitution into headers or form bodies, explicit volumes and sockets | full checkpoints (RAM, CPU, disks), live copy-on-write branches, portable `.smolmachine` packs, cross-arch Mac to Linux |
| **krun** (crun) | `krun` is a symlink to `crun`; Podman runs an OCI container inside a libkrun microVM | hardware microVM with the container's namespaces and cgroups set up first | networking in TSI (default, socket proxy), passt or TAP; virtio-blk, virtio-fs, virtio-console | the container's, no VM-level checkpoint |

Three names collide here and should not be conflated. `podman machine
--provider libkrun` is Podman's own host VM on macOS, not workload isolation.
`crun`'s `krun` mode is the OCI container in a microVM. `crun-vm` is a third
thing: an OCI runtime that boots full QEMU VM images with cloud-init or
Ignition, for bootable containers — prior art, not this boundary.

### What they actually promise

| promise | Gondolin | smolvm | krun |
| --- | --- | --- | --- |
| guest code does not run on the host kernel | yes | yes | yes |
| egress confined by policy | yes, deep: HTTP/1.1 parsing and TLS interception, DNS modes, no generic NAT | yes, coarse: allowlist and a per-flow decider | no policy of its own; whatever the host network and Podman give it |
| the guest can use a secret without reading it | yes, placeholders substituted per host | yes, placeholders in headers or form bodies | no |
| host filesystem hidden unless granted | yes, every mount is a host-side provider | no — a mounted directory is plaintext to the guest and the host | yes via virtio-fs, host-mediated |
| state can be snapshotted | disk only | RAM + CPU + disks, and branched | no |
| explicit non-goals | malicious host, malicious local user, VM escape, side channels, DoS | not a multi-user control plane; the invoking user is in the TCB; releases are checksummed but not signed | inherits libkrun's device model and TSI caveats |

Two things are worth stating plainly.

First, **all three are "guest adversarial, host trusted"**. Gondolin says the
host process, the daemon and the machine are trusted; smolvm says the invoking
user, the host OS, libkrun and smolvm are in the TCB; krun inherits whatever
the host grants. None of them answers "can the host read my data?" — the host
mediates the plaintext, by design. If the storage design's answer is "the host
must not read", the guest still has to hold the key (previous section), and
these projects are about the *other* direction.

Second, **libkrun's own security model bounds all of them**. The VM boundary
does not restrict host resources exposed through devices; the virtio-fs export
path is not a sandbox; TSI proxies sockets with the VMM's host identity and can
reach the VMM's Unix sockets. A product can add policy on top, as Gondolin and
smolvm do, but it cannot exceed the boundary underneath.

### What is most promising to study

1. **Gondolin's I/O mediation triad** — deny-by-default egress, placeholder
   secrets bound to hosts, and a fully programmable filesystem — is the most
   reusable idea in the three. It is the network-layer analogue of the storage
   note's key daemon: the workload holds a handle it can use but not read, and
   the policy point decides when the real value appears. Its `security.md`
   shape (goals, non-goals, trust assumptions, guarantees, safe envelope) is
   also the right template for any isolation claim this tree makes.
2. **Gondolin's control plane over virtio-serial**, not a network service, is a
   small attack surface worth copying: the guest cannot dial a host port, and
   the host's authority is a pair of pipes it owns.
3. **smolvm's VMM confinement**: running the VMM as a separate `smol-vmm`
   helper under seccomp and Landlock means a guest escape lands in a confined
   process rather than in the application. That is cheap defence in depth and
   independent of which VMM is used.
4. **smolvm's defaults** — networking off, every mount, socket and port is
   explicit authority, guest root is untrusted — match the ladder's default
   deny and are the right posture for this host.
5. **krun's OCI integration** is the cheapest way to give one workload a VM
   boundary without changing the orchestrator: the image stays an OCI image,
   the lifecycle stays a Podman container, and only the runtime changes (with
   the Quadlet `.service` caveat above).
6. **smolvm's branch and checkpoint** is the standout feature for agent
   workflows — rewind a running machine, branch it copy-on-write — and the
   least relevant to a storage node.

### What to hold as prior art

- **Gondolin itself**: the userspace netstack, TLS interception, VFS provider
  protocol and Alpine-only image builder are a coherent design but far more
  machinery than a home pool should run, and the TLS MITM means host-trusted by
  construction. Study the pattern, do not deploy the product.
- **smolvm's cloud transport, pack format and branching**: excellent for agent
  development and stateful sandboxes; alpha software, unsigned releases, and a
  different problem from durable storage.
- **crun-vm**: full VM images as containers, QEMU and cloud-init. A useful
  reference for "a VM as a Podman workload", not for microVM isolation.
- **`podman machine --provider libkrun`**: the macOS host VM. It shows libkrun
  is production-adjacent inside Podman, nothing more.

### The result for this host

- For one workload that must be isolated now: `crun`'s `krun`, a `.service`
  with `podman run --runtime=krun`, networking through passt or TAP rather than
  TSI, and no virtio-fs export into an untrusted guest.
- For agent or otherwise untrusted code that needs credentials: copy Gondolin's
  mediation pattern (placeholders, host binding, deny by default), not its
  stack; take smolvm's confined-VMM and networking-off defaults as the baseline.
- Do not read any of the three as "the host cannot see the data". That requires
  guest-side keys and, if host root must be excluded, a confidential guest.

## systemd and k3s/k0s

The VM boundary is orchestration-agnostic; the integration is not.

| host model | how a VM is declared | maturity | cost |
| --- | --- | --- | --- |
| plain unit | one `.service` per VM, `ExecStart` the VMM, `Type=notify`/`Type=exec`, an API socket, a vsock agent for lifecycle and key delivery | works today, no extra daemon | you own the boot, shutdown and health logic |
| `systemd-vmspawn` | a systemd-native VM spawner | experimental, QEMU only | attractive shape, not a production base yet |
| libvirt | a domain XML, `virtqemud` (modular daemons), `virsh` | mature | a daemon, polkit, XML, but solved shutdown, consoles and migration |
| microvm.nix | a NixOS microVM as a package and a systemd service, several hypervisors | NixOS-only | the cleanest declarative model if the host is NixOS |
| Quadlet | no VM support | — | a `.container` cannot launch a VM; the pinned Podman's Quadlet has no runtime key, so a krun workload is a plain `.service` running `podman run --runtime=krun`, not a `.container` |

| cluster model | how a VM is declared | needs | cost |
| --- | --- | --- | --- |
| k3s/k0s + Kata | a pod with `runtimeClassName: kata-qemu` (or `kata-clh`, `kata-fc`); `kata-deploy` has a k3s overlay | `/dev/kvm`, a containerd shim, node labels | a runtime class, per-node install, guest kernel management |
| k3s/k0s + KubeVirt | a `VirtualMachine` CRD; each VM runs in a `virt-launcher` pod with libvirt/QEMU inside | privileged pods, a KVM device plugin, CRDs and controllers | a control plane plus a VM operator; live migration and hotplug are the payoff |
| Kuasar | a sandbox abstraction over microVM, app-kernel and wasm sandboxes | a runtime and per-sandbox tooling | interesting prior art, another moving part |
| firecracker-containerd | containerd shim with a microVM per pod | containerd, `/dev/kvm` | the older AWS pattern, largely superseded by Kata |

The honest summary: **viable in both, and worth it in neither by itself.** A
single-host setup pays one unit per VM and gets the boundary without a control
plane. A k3s/k0s setup pays a RuntimeClass or a CRD and gets scheduling and
declarative lifecycle — but that is the same control plane the storage note
already declined to add, and adding it for VMs alone would be the tail wagging
the dog.

The cheapest composable step on this host is `crun` with libkrun: the workload
stays a Podman container, gets a VM boundary, and keeps the Quadlet-to-systemd
story — minus the `Runtime=` key, so it becomes a `.service` rather than a
`.container`.

## Nesting

Nesting works mechanically: KVM inside KVM, `nested` enabled by default since
Linux 4.20 (distributions may override), a guest hypervisor started with
`-cpu host` or an explicit `vmx=on`. What it does not do is add a hardware
boundary.

- **L1 is in L2's TCB.** A compromised L1 hypervisor owns every L2 beneath it.
  Nesting adds a hypervisor to trust, not a wall to trust less.
- **L0 sees L1 unless L1 is confidential.** Without SEV-SNP/TDX, the outer host
  can read the inner hypervisor's memory, and therefore everything it can read.
- **Confidential guests do not nest.** SEV-SNP and TDX have no supported
  nesting; AMD's VMPL levels are a privilege split inside one guest, not a
  chain of isolated hypervisors. A confidential L1 cannot host an L2 that L1 is
  protected from.
- **The edges are sharp.** On AMD, migrating or saving an L1 while an L2 runs is
  undefined behaviour per the kernel documentation; nested KVM loses features
  and performance, and debugging spans three kernels.
- **Two VMMs and two guest kernels are two more patch targets**, each with the
  device-model surface described above.

So nesting is an **administrative** boundary. It is right when the inner
administrator is a different person or tenant from the outer one — a delegated
environment where the platform runs the L1 and the tenant runs containers or
VMs inside it, and the platform does not want to manage the inner lifecycle. It
is wrong as a substitute for confidential computing, and it is wrong as "more
layers must be safer": the security of the chain is the weakest hypervisor in
it.

## Layering trust without nesting

The useful way to layer is **siblings with different key scopes**, not nested
hypervisors. The host, the storage engine and the workloads each get one job
and one set of secrets.

| layer | runs | holds | can read data? |
| --- | --- | --- | --- |
| host | KVM, devices, media | no keys; ciphertext on disk | no, if keys never enter host memory |
| storage VM | the object core: format, placement, verify, repair | disk LUKS keys for its own media | no — it moves ciphertext |
| key and attestation VM | the key daemon, vTPM, remote attestation | the root key; KEK wrapping | no — it issues wraps, not keys to data |
| workload VM | the application, the object client, the FUSE mount | its own KEK | yes, its own subtree only |

With confidential guests (SEV-SNP/TDX), the host moves outside the TCB and the
table becomes true in the strong sense: the host cannot read guest memory even
with root. Without them, the host can dump guest RAM, so the layering reduces
blast radius and keeps the storage engine honest, but it does not remove host
root from the trust model. Both outcomes are useful; only one is
"confidential", and the difference should be written down.

The boot chain is what makes the claim checkable: a UKI, a vTPM (`swtpm`), PCR
measurements of firmware, kernel and initrd, and a remote verifier such as
Keylime that releases a key only for an attested measurement. Two caveats: a
vTPM state file lives on the host, so without a TEE it protects against a
stolen disk rather than a hostile host; and an attestation that nobody verifies
is decoration.

## Distribution over more machines

More machines is an availability decision that is often mistaken for a security
decision.

| effect | direction | why |
| --- | --- | --- |
| failure domains (power, PSU, controller, host) | better | independent copies survive what one machine cannot |
| blast radius per compromise | better | one workload per machine limits what a single escape reaches |
| key custody | worse | keys either spread to every node or centralise into a service that becomes the target |
| network as a trust boundary | worse | mTLS, authentication, and a new place for plaintext to appear in transit |
| patch and supply-chain surface | worse | N kernels, N VMMs, N images, N update paths |
| attestation and observability | worse | each node needs its own measured boot and its own verification |
| "who can read the data" | worse unless designed | every node that holds a key is a reader; only ciphertext-holding nodes are not |

The conditions under which distribution is neutral or positive are narrow and
already implied by the storage design: **clients hold the keys, nodes hold
ciphertext, copies are object-level and independently verifiable, and each node
is attested.** Under those conditions a second machine buys availability and
fault independence at no confidentiality cost. Without them it buys
availability by widening the set of parties who can read the data.

At home, two or three machines covers the failure domains that actually occur
(one PSU, one host, one controller). Beyond that the marginal security is
negative and the marginal availability is small. Note also that this is
distributed *storage nodes*, not a distributed filesystem: no shared
namespace, no remote clients, no metadata service on the network — the cut from
the storage note survives.

## What would be necessary

- **Decisions:** is host root inside the threat model (if yes, confidential
  guests or a second machine); which rung each workload occupies; whether the
  key lives in the guest or on the host; how many machines and why.
- **Artifacts:** a per-workload VM declaration (image digest, device list, rung,
  key scope, attestation policy); an image build with a UKI and a read-only
  root; a vsock control protocol; a key-release policy; a nested-VM policy that
  says "delegation only" or "never".
- **Components:** one VMM per class (libkrun for the cheap boundary, Cloud
  Hypervisor when virtio-fs or passthrough is needed, Firecracker where the
  device list must be minimal); the guest-side object client; the key daemon;
  the attestation verifier; a unit-per-VM pattern or a RuntimeClass.
- **Tests:** kill the VMM mid-write and prove the object layer recovers; attempt
  a virtio-fs escape through a symlink and prove the export is narrow; prove
  the host cannot read a guest's key (and record whether that is by policy or by
  hardware); measure nested I/O and boot cost; fail attestation and prove the
  key is not released; lose a node and restore from an independent copy.

## Issues that will bite

1. **A shared directory leaks plaintext to the host.** virtio-fs, 9p and NFS
   all do; only a guest-side client or a guest-unlocked block device does not.
2. **The device model is the attack surface.** Minimal devices, no PCI, USB or
   GPU into untrusted guests, and seccomp/jailer where the VMM offers one.
3. **vsock is a channel, not an authentication.** libkrun's control socket is
   protected only by Unix permissions on its path; treat it as root-equivalent
   and put it where only the runtime can reach it.
4. **virtio-fs needs quotas and a narrow export.** A guest can exhaust inodes,
   descriptors and disk; libkrun's own model says so.
5. **Attestation without verification is theatre.** A vTPM and a measured boot
   only matter if a verifier checks PCRs and refuses the key.
6. **Nesting is not a security amplifier.** L1 owns L2, L0 owns L1, confidential
   guests do not nest, and AMD migration with a live L2 is undefined.
7. **Kubernetes integration is not free.** Kata needs `/dev/kvm`, a shim and a
   RuntimeClass; KubeVirt needs privileged pods and a device plugin.
8. **Quadlet cannot select a runtime** in the pinned Podman, so the krun path is
   a plain `.service`, not a `.container`.
9. **Density costs are recurring.** One guest kernel per workload to patch, one
   boot per restart, duplicated page cache.
10. **Distribution multiplies key custody and patch surface** before it improves
    anything; it is an availability tool.
11. **GPU passthrough is the only real GPU boundary**, and it takes the device
    from the host; virtio-gpu/venus shares the host driver (the
    [GPU note](gpu-and-display-isolation.md) records the detail).
12. **Confidential guests have feature holes** — no memory or CPU hotplug, no
    hugepages, no vIOMMU or vDPA with SEV-SNP — which change what the storage
    VM can do.

## Verdict

- **Default:** containers for trusted, single-tenant services; a microVM for
  anything exposed or untrusted; block and GPU as exceptions.
- **Cheapest boundary that keeps the current model:** `crun`/libkrun under
  Podman, as a `.service`. It adds a VM without a control plane, at the cost of
  Quadlet's `.container` form.
- **When the device model must be minimal:** Firecracker, accepting no
  virtio-fs (images arrive as block devices) and no confidential guests.
- **When virtio-fs, passthrough or SEV-SNP is needed:** Cloud Hypervisor, with
  its SNP limitations recorded.
- **On k3s/k0s:** Kata when the cluster already exists; KubeVirt only for real
  VM lifecycle needs. Neither is a reason to adopt a cluster.
- **For maximum safety:** put the key in the guest, expose the object API rather
  than a directory, and use confidential guests if host root must be outside
  the model. Accept the guest-side client as the price.
- **Nesting:** for delegation and testing only; otherwise use siblings.
- **More machines:** for failure domains only, with ciphertext-only nodes and
  client-held keys.
- **Sandbox projects:** study Gondolin's mediation pattern, take smolvm's
  networking-off and confined-VMM defaults, and use krun for the cheapest OCI
  boundary; none of them moves host root out of the trust model.

## Open questions

1. Is host root inside the threat model? If not, the VM layer is about blast
   radius and the cheaper devices are fine.
2. Which workloads can live with an object API in the guest, and which need a
   shared directory (and therefore a trusted host)?
3. Is the CPU confidential-capable (SEV-SNP or TDX), and does the chosen VMM
   support it with the devices the storage VM needs?
4. Is a second machine available for real failure domains, and would it hold
   ciphertext only?
5. Does the per-VM patch burden fit the upkeep budget, or does it argue for
   fewer, larger VMs?
6. Is the nested case actually delegation, or is it a substitute for a
   confidential host?

## Status

Draft assessment. No VMM, unit, image or cluster was installed. The claims are
from the vendored sources named above and the earlier notes in this tree; no
host was queried and nothing outside this note and the index was changed.
