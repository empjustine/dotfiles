---
id: research-microvm-composition
type: architecture-design
status: draft
title: "VMs and microVMs: trust direction, krun networking, virtio-fs and distribution"
parent: index
references: [index, research-storage-overlay, research-workload-isolation-egress, research-multi-uid-access, research-files-volumes, research-quadronegro-availability-threats, research-gpu-display-isolation, decision-log]
---

# VMs and microVMs: trust direction, krun networking, virtio-fs and distribution

The [storage note](storage-overlay.md) ends with an open question — is host
root inside the threat model? The answer for this pool is **no, and that is
deliberate**. The host is trusted, the guest is not, and being able to inspect
a guest is a feature rather than a leak. This revision says so explicitly,
withdraws "confidential guest" from the goal set, verifies the three krun
networking modes, and answers whether a virtio-fs export of our own FUSE view
can be made safe.

Claims about the VMMs are read from the vendored trees (Firecracker, Cloud
Hypervisor, libkrun, Kata, Kuasar, microvm.nix, Keylime), the sandbox projects
(Gondolin, smolvm, crun and crun-vm), the kernel's nested KVM documentation,
the virtiofsd and passt documentation, and the earlier notes in this tree.
Nothing was run.

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

## Where the plaintext lives

| interface | host sees plaintext | guest sees plaintext | notes |
| --- | --- | --- | --- |
| bind mount / host FUSE | yes | yes | the container model |
| virtio-fs | yes — virtiofsd serves the decrypted tree | yes | the export path is a capability grant |
| 9p | yes | yes | weaker model than virtio-fs; avoid for untrusted guests |
| NFS | yes — the server decrypts | yes | `sec=krb5p` authenticates the client, it does not hide content from the server |
| virtio-blk + LUKS in the guest | no — ciphertext blocks | yes | strong against the host; loses object-level FEC and partial recovery |
| object API with the client in the guest | no | yes | keeps R1/R2 intact across the boundary |

Those rows describe *which* boundary is being crossed, not which one is
required. With a trusted host the first four are acceptable, and the last two
are for the different threat in which the *provider* or a stolen disk is the
adversary — the threat the storage design's client-side keys already address.

## Trust direction: the host is trusted on purpose

The threat model that fits this pool is the one Gondolin writes down explicitly
and smolvm states in its security model: **the guest is adversarial, the host
is the enforcement point**. Gondolin's non-goals include a malicious host, a
malicious local user, VM escape and side channels; smolvm names the invoking
user, the host OS, libkrun and itself as trusted. That is the correct model
here, and it has three consequences.

**Confidential guests are not a goal.** SEV-SNP and TDX are for hardware whose
owner is not the person running the workload — a cloud tenant. Here the owner
*is* the operator; the host holds the disks, the keys and the backups anyway.
Making the guest unreadable to its owner buys nothing and costs the things that
are useful:

- **inspection as an incident tool** — freeze a compromised guest, dump its
  RAM, attach `gdb`, read its page cache, take a crash snapshot, and reconstruct
  what it did. That is how a workload becomes accountable rather than merely
  contained;
- **inspection as a debugging tool** — the same dump answers "why did this
  service die at 03:00" without reproducing it;
- **inspection as a storage-verification tool** — the host can compare what a
  workload believes it wrote with what the object layer holds.

**It is also mostly unreachable here.** SEV-SNP needs an EPYC-class CPU with
the feature enabled in firmware; TDX needs a recent Xeon; both need kernel and
VMM support and, for anything stronger than "the hypervisor cannot read
memory", an attestation service and a pinned policy. Consumer platforms are
inconsistent or absent. Even where the hardware exists, Cloud Hypervisor's
SEV-SNP support gives up memory and CPU hotplug, hugepages, the virtual IOMMU
and vDPA, and SEV-SNP/TDX do not nest. It is a platform project, not a flag.

**Per-workload keys still matter, for a different adversary.** They stop a
storage provider, a stolen disk, a copied backup and another workload. They do
not stop the host, and with the host trusted they do not need to. The key
question is not "can the guest hide from the host" but "can the guest reach
data outside its own subtree, and can the provider read it".

## Overhead

| VMM | device model | density and boot | virtio-fs | confidential guests | notes |
| --- | --- | --- | --- | --- | --- |
| Firecracker | block, net, vsock, serial; no PCI, no GPU | VMM threads ≤ 5 MiB, 5 microVMs per core-second at 128 MiB guest RAM | no | no | the smallest surface; a container image must arrive as a block device |
| Cloud Hypervisor | virtio block/net/fs, hotplug, VFIO, vhost-user | low footprint; a full Rust VMM | yes, with DAX | SEV-SNP, with the feature losses above | the practical middle: virtio-fs and passthrough when needed |
| libkrun | virtio console/block/fs/net/vsock/balloon/gpu | a library inside the runtime, no separate VMM process | yes | SEV and TDX variants exist | the cheapest way to keep Podman: `crun` runs the workload under `--runtime=krun` |
| Kata Containers | VM per pod, QEMU/Cloud Hypervisor/Firecracker backends | container-shaped lifecycle, VM-shaped isolation | backend-dependent | CoCo configs exist | the Kubernetes answer; a containerd shim and a RuntimeClass |
| QEMU (full) | everything | largest memory and surface | yes | SEV/SNP/TDX with configuration | the compatibility choice, not the minimal one |
| systemd-nspawn | none — namespace container | container | n/a | no | not a VM boundary |

Three rules follow.

- **The smallest device model that carries the needed interface.** For an
  object-only workload that is virtio-net plus vsock; for `files` it is
  virtio-fs; block and GPU are exceptions.
- **Per-VM kernel means per-VM patching.** Density is not only RAM: every guest
  kernel is a patch target, and every VM boot is a page-cache cold start.
- **Confidential guests change the arithmetic in the wrong direction.** They
  remove the inspection tools the pre-header above relies on, for a threat that
  is not present.

## Sandbox projects: Gondolin, smolvm and krun

Three projects turn "microVM for untrusted work" into a product. All three
assume a trusted host, which is why they are the right prior art for this
question and the wrong prior art for "host root must be excluded".

| project | shape | mediation | state |
| --- | --- | --- | --- |
| **Gondolin** (earendil-works) | TypeScript SDK + CLI, Rust daemon `gondolind`, guest Alpine, libkrun default and QEMU fallback | userspace netstack: allowlist, internal-range blocking, DNS modes, HTTP/1.1 TLS interception, SSH egress proxy, mapped TCP; placeholder secrets substituted per allowed host; programmable VFS (FUSE over virtio-serial, or virtio-fs) | disk-only qcow2 checkpoints |
| **smolvm** (smol-machines) | CLI + Node/Python/Rust/Go SDKs, bundled libkrun, OCI images, local and cloud transports | networking **off by default**, `allow_hosts`, a mediated-egress decider (allow/deny/redirect, no TLS inspection), credential substitution into headers or form bodies, explicit volumes and sockets; `smol-vmm` confined by seccomp and Landlock | full checkpoints (RAM, CPU, disks), copy-on-write branches, portable packs |
| **krun** (crun) | `krun` is a symlink to `crun`; Podman runs an OCI container inside a libkrun microVM | networking in TSI (default), passt or TAP; virtio-blk, virtio-fs, virtio-console | the container's; no VM-level checkpoint |

Three names collide here and should not be conflated. `podman machine
--provider libkrun` is Podman's own host VM on macOS, not workload isolation.
`crun`'s `krun` mode is the OCI container in a microVM. `crun-vm` boots full
QEMU VM images with cloud-init or Ignition, for bootable containers.

The promises worth studying are Gondolin's I/O mediation triad (deny by
default, placeholder secrets bound to hosts, programmable filesystem), its
`security.md` shape as a template for making an isolation claim checkable,
smolvm's VMM confinement under seccomp and Landlock, and smolvm's defaults
(networking off, every mount and socket is explicit authority). Gondolin's
full netstack and TLS interception, smolvm's cloud transport and packing, and
`crun-vm` stay reference only: the first is more machinery than this pool needs
and the last two are different problems.

## krun networking: TSI, passt and TAP

The three modes are not three settings of one thing; they place the guest at
three different points relative to the host network.

| | TSI | passt | TAP |
| --- | --- | --- | --- |
| mechanism | the guest kernel hooks `socket`/`connect`/`bind`/`listen`/`accept` and multiplexes them over virtio-vsock; the VMM performs the calls | a userspace proxy on a virtio-net interface, connected over a Unix socket | a virtio-net device attached to an existing host TAP and bridge |
| guest interface | none — no NIC, no IP, no DHCP | `eth0`, private IP, NAT | `eth0`, layer 2 |
| network identity | the VMM's network namespace and addresses; connections originate from the host's IPs | the guest's private address, translated by passt | the guest's own MAC/IP on the attached segment |
| egress control | confine the VMM's network namespace or firewall it; the guest uses the host's routing table | host firewall plus passt's forwarding rules; `--no-map-gw` blocks the guest's path to host services through the gateway | bridge and netfilter, entirely yours to write |
| inbound | TCP port forwarding, plus **automatic exposure of application-selected ports** | passt is started with `-t all -u all`, so every guest TCP/UDP listener is forwarded to the host at the same port | host netfilter or bridge configuration |
| DNS | the host's resolver, since the VMM's context is used | none from crun (`--no-dhcp-dns`); the guest needs its own `resolv.conf` | whatever the segment provides |
| unusual reach | `AF_UNIX` hijacking on Linux lets the guest reach host sockets the VMM can | none beyond the forwarded ports | full L2: ARP, broadcast, multicast |
| privilege and setup | none | none; passt runs as a child of crun, privileged ports need a capability or sysctl | a TAP usable by the VMM user and `/dev/net/tun`; creating one needs `CAP_NET_ADMIN`, so rootful or pre-created |
| performance | a proxy per socket, no guest network stack | one proxy for the VM, user-space NAT | native, the best throughput |
| failure modes | guest `listen()` can succeed with a guest-only listener when the host bind fails; a hostile guest can exhaust VMM file descriptors and send buffers unless the proxy limit and send-queue budget are set | passt is a C parser in the data path; every forwarded port is a host listener; no DNS unless configured | misconfiguration is silent: wrong routes, wrong bridge, exposed segment |

The trade-off, stated plainly:

- **TSI is the least isolated by default**, because "transparent" means the guest
  inherits the VMM's network identity, the guest's listeners are published
  automatically, and `AF_UNIX` hijacking hands the guest every host socket the
  VMM can reach. It is also the only mode with no guest network stack to
  configure. Use it when the workload is trusted-ish, or confine the VMM in a
  dedicated network namespace with a firewall and accept the rest.
- **passt is the sensible default for an untrusted guest**: the guest gets its
  own address and a conventional NIC, host services are not reachable through
  the gateway (`--no-map-gw`), and the host firewall applies. Its two sharp
  edges are that `-t all -u all` publishes every guest listener and that crun
  does not configure DNS.
- **TAP is the most control and the most responsibility**: full layer 2,
  native performance, and every isolation property depends on the bridge and
  firewall being right. It also needs privileges the other two do not.

None of the three replaces a per-workload network namespace. libkrun's own
security model says to restrict the VMM's network permissions, and that advice
applies to all three modes.

## virtio-fs and a FUSE view

The question is whether exporting *our* FUSE view over virtio-fs is safe, or
whether that is inherently impossible. The short answer: **content confinement
yes, host confidentiality no, and stacked FUSE is the fragile part.**

What the daemon actually does (from the virtiofsd documentation):

- it runs as root, or as fake root inside a user namespace, and it must be able
  to create and access files as any uid/gid;
- it applies seccomp and drops capabilities to a small set (ownership and
  ownership-changing calls), so it is a privileged process by construction;
- the default sandbox is `namespace`: a new mount, PID and network namespace
  plus `pivot_root` into the exported tree, which is what prevents symlink and
  `..` escapes out of the export;
- xattrs, POSIX ACLs and security labels are off by default; enabling any of
  them needs a mapping, and `modcaps=+sys_admin` for `trusted.*` raises the
  blast radius;
- the FUSE requests carry a uid/gid supplied by the guest kernel. A hostile
  guest can assert any identity, so **ownership and ACLs inside the export are
  not a boundary against the guest; the set of what is exported is.**

Given that, a virtio-fs export of our FUSE view gives exactly the policy the
view implements — one workload's subtree, read-only if asked, no path outside
it — and it can be made *reasonably safe in the guest direction* with the
sandbox, a single narrow export, no xattrs, no ACLs, no security labels,
`RLIMIT_NOFILE`, and quotas so the guest cannot exhaust host descriptors or
inodes. It is not a confidentiality boundary: the daemon and the host see the
decrypted tree, by design, and the host is trusted.

The part that is genuinely problematic is **stacking FUSE on FUSE**: guest
FUSE → virtiofsd → the kernel's FUSE mount → our FUSE daemon. In that chain

- inode file handles need `name_to_handle_at`, which FUSE filesystems generally
  do not support, so the daemon falls back to holding an `O_PATH` descriptor per
  inode — fine until the export is large or metadata-heavy;
- DAX cannot share the page cache of a file that the host does not cache, so
  the fast path disappears;
- xattrs, ACLs and security labels have to be mapped through two layers, and
  the mapping has to be right or the guest can reach attributes the host
  intended to keep;
- every operation pays two userspace round trips, and the failure modes of the
  inner FUSE daemon become visible as strange errno values in the guest;
- a guest can still DoS the outer daemon with metadata churn, which is a host
  resource problem.

So it is not "inherently impossible", but it is the wrong shape. In descending
order of preference:

1. **Export a plain directory.** Materialise the per-workload view as ordinary
   files (a bind of the subtree, or a materialised decrypted tree) and export
   that. One filesystem, no stacking, no file-handle fallback, and the
   encryption boundary stays where the storage design put it.
2. **Put the FUSE client in the guest.** Expose the object API over virtio-net
   or a vsock proxy and let the guest mount its own view. This is the only
   arrangement that also keeps the host out of the plaintext, and it costs a
   guest-side client.
3. **Export the live FUSE view anyway**, treating virtiofsd as an
   untrusted-facing privileged daemon: one export per workload, `sandbox=namespace`,
   xattrs and ACLs off, read-only unless writes are required, `RLIMIT_NOFILE`
   and quotas, and the expectation that the daemon is in the host's TCB and its
   CVEs are host CVEs.

## systemd and k3s/k0s

The VM boundary is orchestration-agnostic; the integration is not.

| host model | how a VM is declared | maturity | cost |
| --- | --- | --- | --- |
| plain unit | one `.service` per VM, `ExecStart` the VMM, `Type=notify`/`Type=exec`, an API socket, a vsock agent for lifecycle and key delivery | works today, no extra daemon | you own the boot, shutdown and health logic |
| `systemd-vmspawn` | a systemd-native VM spawner | experimental, QEMU only | attractive shape, not a production base yet |
| libvirt | a domain XML, `virtqemud` (modular daemons), `virsh` | mature | a daemon, polkit, XML, but solved shutdown, consoles and migration |
| microvm.nix | a NixOS microVM as a package and a systemd service, several hypervisors | NixOS-only | the cleanest declarative model if the host is NixOS |
| Quadlet | no VM support | — | a `.container` cannot launch a VM; the pinned Podman's Quadlet has no runtime key, so a krun workload is a plain `.service` running `podman run --runtime=krun` |

| cluster model | how a VM is declared | needs | cost |
| --- | --- | --- | --- |
| k3s/k0s + Kata | a pod with `runtimeClassName: kata-qemu` (or `kata-clh`, `kata-fc`); `kata-deploy` has a k3s overlay | `/dev/kvm`, a containerd shim, node labels | a runtime class, per-node install, guest kernel management |
| k3s/k0s + KubeVirt | a `VirtualMachine` CRD; each VM runs in a `virt-launcher` pod with libvirt/QEMU inside | privileged pods, a KVM device plugin, CRDs and controllers | a control plane plus a VM operator |
| Kuasar | a sandbox abstraction over microVM, app-kernel and wasm sandboxes | a runtime and per-sandbox tooling | another moving part |
| firecracker-containerd | containerd shim with a microVM per pod | containerd, `/dev/kvm` | the older AWS pattern, largely superseded by Kata |

**Viable in both, and worth it in neither by itself.** A single-host setup pays
one unit per VM and gets the boundary without a control plane. A k3s/k0s setup
pays a RuntimeClass or a CRD and gets scheduling and declarative lifecycle —
the same control plane the storage note already declined, so adding it for VMs
alone would be the tail wagging the dog.

## Nesting

Nesting works mechanically: KVM inside KVM, `nested` enabled by default since
Linux 4.20 (distributions may override), a guest hypervisor started with
`-cpu host` or an explicit `vmx=on`. It does not add a hardware boundary.

- **L1 is in L2's TCB.** A compromised L1 hypervisor owns every L2 beneath it.
- **L0 sees L1.** Without confidential memory, the outer host can read the
  inner hypervisor's memory, and therefore everything under it.
- **Confidential guests do not nest.** SEV-SNP and TDX have no supported
  nesting; AMD's VMPL levels are a privilege split inside one guest, not a chain
  of isolated hypervisors.
- **The edges are sharp.** On AMD, migrating or saving an L1 while an L2 runs is
  undefined behaviour per the kernel documentation; nested KVM loses features
  and performance, and debugging spans three kernels.
- **Two VMMs and two guest kernels are two more patch targets.**

Nesting is an **administrative** boundary: right when the inner administrator
is a different person or tenant from the outer one, wrong as a substitute for
isolation you do not have, and wrong as "more layers must be safer".

## Layering trust without nesting

The useful layering is **siblings with different key scopes and different
jobs**, not nested hypervisors. With a trusted host the table is about blast
radius and separation of duties, not secrecy from the host.

| layer | runs | holds | purpose |
| --- | --- | --- | --- |
| host | KVM, devices, media, inspection tools | no workload keys; ciphertext and the decrypted views it serves | the enforcement point, and the place a compromised guest is examined |
| storage VM | the object core: format, placement, verify, repair | disk LUKS keys for its own media | keeps storage maintenance out of the host and off the workloads |
| key and attestation VM | the key daemon, vTPM | the root key and the wraps | separation of duties: issuing a KEK does not require data access |
| workload VM | the application, the object client, the FUSE mount | its own KEK | the untrusted zone |

A vTPM, a UKI and a measured boot are still worth having — for *reproducibility*
and for knowing which image a guest actually booted, not for keeping the host
out. An attestation verifier is optional at home; if nobody checks the PCRs,
the measurement is a log line, not a control.

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

Distribution is neutral or positive only under the conditions the storage
design already implies: **clients hold the keys, nodes hold ciphertext, copies
are object-level and independently verifiable.** Then a second machine buys
availability and fault independence at no confidentiality cost. Without them
it buys availability by widening the set of parties who can read the data.

At home, two or three machines covers the failure domains that actually occur
(one PSU, one host, one controller). Beyond that the marginal security is
negative and the marginal availability is small. And it stays distributed
*storage nodes*, not a distributed filesystem: no shared namespace, no remote
clients, no metadata service on the network.

## What would be necessary

- **Decisions:** the host is trusted (recorded); which rung each workload
  occupies; which network mode each workload gets; whether a virtio-fs export
  is needed at all; how many machines and why.
- **Artifacts:** a per-workload VM declaration (image digest, device list, rung,
  key scope, network mode); an image build with a read-only root; a vsock or
  serial control protocol; a per-network-mode firewall policy; a nested-VM
  policy that says "delegation only" or "never".
- **Components:** one VMM per class (libkrun for the cheap boundary, Cloud
  Hypervisor when virtio-fs or passthrough is needed, Firecracker where the
  device list must be minimal); the guest-side object client if the provider is
  the adversary; the key daemon; an inspection path (dump, console, snapshot).
- **Tests:** kill the VMM mid-write and prove the object layer recovers; attempt
  a symlink escape through the export and prove the sandbox holds; assert that
  a guest cannot reach a host socket through TSI; prove passt does not expose
  the guest beyond the intended ports; measure stacked-FUSE cost if it is used;
  lose a node and restore from an independent copy.

## Issues that will bite

1. **TSI hands the guest the VMM's identity.** Host addresses, host routing,
   automatic exposure of guest listeners, and `AF_UNIX` reachability. Confine
   the VMM in its own network namespace or do not use TSI for untrusted work.
2. **passt publishes every guest listener.** `-t all -u all` is convenient and
   is a host exposure; the listen address is not pinned by crun, and DNS is not
   configured for the guest.
3. **TAP moves the whole isolation problem into your bridge and firewall.** It
   needs privileges, and misconfiguration fails open rather than closed.
4. **virtiofsd is a privileged daemon in the host's TCB.** Root or fake root,
   ownership-changing capabilities, and the guest's uid/gid asserted in the
   protocol — the export set is the boundary, not the ownership inside it.
5. **Stacked FUSE is fragile.** File-handle fallback, FD pressure, no DAX,
   double mapping of xattrs and ACLs, and two userspace hops per operation.
6. **xattrs, ACLs and security labels are a policy decision.** They are off by
   default; enabling them without a mapping lets the guest reach attributes the
   host meant to keep.
7. **A guest can DoS the VMM or the daemon** unless proxy limits, send-queue
   budgets, `RLIMIT_NOFILE` and quotas are set; libkrun leaves the first two
   unbounded by default.
8. **Confidential guests would remove the inspection tools** and are not
   reachable on this hardware class anyway; do not design around them.
9. **Nesting is not a security amplifier**, and confidential guests do not nest.
10. **Kubernetes integration is not free.** Kata needs `/dev/kvm`, a shim and a
    RuntimeClass; KubeVirt needs privileged pods and a device plugin.
11. **Quadlet cannot select a runtime** in the pinned Podman, so the krun path
    is a plain `.service`.
12. **Density costs are recurring.** One guest kernel per workload to patch, one
    boot per restart, duplicated page cache.
13. **GPU passthrough is the only real GPU boundary**, and it takes the device
    from the host; virtio-gpu/venus shares the host driver (the
    [GPU note](gpu-and-display-isolation.md) records the detail).

## Verdict

- **Trust direction:** the host is trusted; the guest is not; inspection is a
  feature. Confidential guests are out of scope, not merely expensive.
- **Default:** containers for trusted, single-tenant services; a microVM for
  anything exposed or untrusted; block and GPU as exceptions.
- **Cheapest boundary that keeps the current model:** `crun`/libkrun under
  Podman, as a `.service`. It adds a VM without a control plane, at the cost of
  Quadlet's `.container` form.
- **Networking:** passt for untrusted workloads, with the host firewall and a
  DNS decision; TAP when layer 2 or throughput is required and the bridge is
  under control; TSI only for trusted workloads or inside a dedicated network
  namespace, and never with a guest that might reach host sockets.
- **virtio-fs:** export a plain directory if possible; put the FUSE client in
  the guest if the provider is the adversary; export the live FUSE view only
  with the sandbox, a single narrow export, no xattrs or ACLs, and rlimits.
- **When the device model must be minimal:** Firecracker, accepting no
  virtio-fs and no confidential guests.
- **On k3s/k0s:** Kata when the cluster already exists; KubeVirt only for real
  VM lifecycle needs. Neither is a reason to adopt a cluster.
- **Nesting:** for delegation and testing only; otherwise use siblings.
- **More machines:** for failure domains only, with ciphertext-only nodes and
  client-held keys.
- **Sandbox projects:** study Gondolin's mediation pattern and smolvm's
  networking-off and confined-VMM defaults; use krun for the cheapest OCI
  boundary.

## Open questions

1. Which workloads can live with `passt` and which need `TAP`; does any need
   `TSI` because it expects the host's own network identity?
2. Does the guest need DNS at all under passt, and where would `resolv.conf`
   come from?
3. Is the FUSE view ever exported as a live mount, or can every `files`
   workload be served from a plain per-workload directory?
4. Is there a workload whose secrecy from the *host* matters? If there is, it
   is a separate, hardware-bound project and the inspection tools are lost.
5. Does the per-VM patch burden fit the upkeep budget, or does it argue for
   fewer, larger VMs?
6. Is the nested case actually delegation, or is it a workaround for something
   a sibling VM already solves?

## Status

Draft assessment, third revision. The host-trusted direction is now explicit and
the confidential-guest goal is withdrawn. No VMM, unit, image or cluster was
installed. The claims are from the vendored sources named above and the earlier
notes in this tree; no host was queried.
