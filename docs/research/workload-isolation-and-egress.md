---
id: research-workload-isolation-egress
type: architecture-design
status: draft
title: "Workload isolation and wide-area egress for the three data workloads"
parent: index
references: [index, research-multi-uid-access, research-quadronegro-design, research-quadronegro-audit, research-quadronegro-availability-threats, research-files-volumes, declarative-upkeep-poc, system, decision-log]
---

# Workload isolation and wide-area egress for the three data workloads

This note answers two questions about the workloads that write to the pool —
Syncthing, Transmission and the new `hister-nogon` unit: what it takes to give
each one its own host identity, storage root, mount view and network the way
Android gives every app its own uid, and what happens to inbound connectivity
(UPnP-IGD, NAT-PMP) once the workload stops sharing the host's network stack.
It also records how far a container escape is from host root under that uid
shape. It is a draft design note; nothing here is installed.

The companion documents are [multi-uid access](multi-uid-data-access.md), which
owns the ACL/bind-mount/NFS detail, [the quadronegro design](quadronegro-at-home-design.md),
[the availability and threat register](quadronegro-availability-and-threats.md) and
[the declarative proof of concept](../declarative-upkeep.md).

The physical topology matters for the egress half and is assumed throughout:
one host, one **dumb (unmanaged) switch**, one **MikroTik hEX E50UG** running
RouterOS as the router. The switch is L2-transparent — it forwards 802.1Q-tagged
frames like any other frame and offers no per-port VLAN, no port isolation and
no IGMP snooping — so all VLAN segmentation has to be declared at the two
managed ends: tagged sub-interfaces on the host, VLAN interfaces on the router.

## The shape today

All three workloads are (or would be) Quadlet units in **one** user manager
under uid 1000:

| workload | image | data | network | volume options |
| --- | --- | --- | --- | --- |
| syncthing | `ghcr.io/empjustine/filesynchronization` | `/var/lib/syncthing` | `Network=host` | `:Z,U` |
| transmission | same image | `/var/lib/transmission` | `Network=host` | `:z,U` |
| hister-nogon | `ghcr.io/asciimoo/nogon:latest` | `/hister/data` | `PublishPort=4433:4433` | `:Z,U` |

The third row now exists as `config/quadlet/hister.container` +
`hister-data.volume`, derived from the one-line `podman run` the owner supplied
(`-p 4433:4433 -v hister_data:/hister/data --name hister-nogon`). It is the only
one of the three that publishes a port instead of sharing the host stack, so it
is also the only one whose inbound path is a static router forward rather than
SSDP discovery. Neither a health endpoint nor a stop budget is known: the unit
carries no `HealthCmd` and a 30 s `StopTimeout` that is a placeholder until one
live stop is measured.

Four properties follow from "one user manager, one uid":

- the three containers share the same host DAC identity, so a compromise of one
  can read the others' state through the host kernel (not through the
  container, but after any escape or via `podman` under that user);
- they share one rootless Podman storage root and one user namespace range;
- `U` chowns the bind source to the container user, so the on-disk owner is
  either uid 1000 (`keep-id`) or a subuid — and it does so recursively on every
  start, which is the wrong default for a shared tree;
- `Network=host` means they share the host's stack: same SSDP queries, same
  NAT-PMP client, competing for the same router mappings.

## The Android model, translated

Android gives every app: its own uid/gid (shared `sharedUserId` is frozen), a
private data directory, its own SELinux domain plus an MCS category, a per-app
network stack (`netd` + UID-based routing and firewall), per-app quotas and a
permission system. The Linux pieces that map onto that:

| Android mechanism | Linux/systemd equivalent | exact? |
| --- | --- | --- |
| per-app uid/gid | static uid per workload (`sysusers.d`), one rootless Podman per uid | yes |
| private data dir | `StateDirectory=`, per-workload directory owned by that uid, `:Z` label | yes |
| per-app SELinux domain + category | `container_t` + MCS pair per container; custom types for a real policy | MCS yes, per-app types need policy |
| per-app network stack | one netns per workload (bridge, macvlan or VLAN); `NetNS=`/`Network=` | yes |
| per-app firewall by uid | nftables `meta skuid`/`meta cgroupv2` rules, or `podman network` per workload | partial |
| per-app quota | cgroup slice (`MemoryMax=`, `IOWeight=`), btrfs `qgroup` | yes, additive |
| app ops / permission prompts | no equivalent; policy is static | no |

The gap that matters: Android's uid split is enforced by a *userspace daemon
plus a MAC policy plus per-uid network routing*; on this host the equivalent is
"one login user per workload with linger, a private storage root, a private
netns, a cgroup slice, and SELinux as the last layer". That is achievable, but
it is four mechanisms, not one.

## Minimum steps to start isolating

Ordered so that each step is useful on its own and none of them requires the
next. Steps 1–3 are the identity work the multi-uid note already argues for;
steps 4–7 are what "correctly isolating" adds beyond it.

1. **One host uid per workload** — no shared `deck` for all three. Declarative
   via `/etc/sysusers.d/`:
   ```
   u! u0_syncthing 10201 "syncthing" /var/lib/workloads/u0_syncthing /usr/sbin/nologin
   u! u0_transmission 10202 "transmission" /var/lib/workloads/u0_transmission /usr/sbin/nologin
   u! u0_hister 10203 "hister" /var/lib/workloads/u0_hister /usr/sbin/nologin
   ```
   plus one `/etc/subuid` + `/etc/subgid` line per user, and
   `loginctl enable-linger u0_syncthing …` so each user manager (and its
   Quadlets) starts at boot. The subuid range stays plumbing for container
   root/users; the host uid is the data identity.
2. **Ownership without `U`** — replace `:Z,U`/`:z,U` with a real identity:
   `UserNS=keep-id` so the in-container user maps to the workload's host uid,
   `:Z` (private relabel) on the workload's own directory, `:z` only where a
   tree is genuinely shared, and never `U` on anything but the private dir.
   `U` on a shared tree recursively re-chowns it on every start, which silently
   crosses every other workload's boundary.
3. **One storage root per workload** — implied by step 1 (rootless storage is
   `~/.local/share/containers`), so image and volume state stop being shared.
4. **One cgroup slice per workload** — `[Service] Slice=workload-u0_hister.slice`
   in a Quadlet drop-in (or `Slice=` in the unit where the Quadlet version
   maps it), with `CPUWeight=`, `IOWeight=`, `MemoryMax=`, `TasksMax=`, and
   `Delegate=yes` so podman can create per-container scopes under it. This is
   the "one noisy workload cannot starve the others" half of Android's quotas.
5. **One netns per workload** — no `Network=host`. Give each its own bridge or
   VLAN attachment and publish only the ports it needs. This is also what makes
   step 6 possible, and it is the change that breaks UPnP (see below).
6. **Sandbox knobs that survive a compromise** — `DropCapability=all` plus the
   one or two capabilities the app actually needs, `ReadOnly=true` with an
   explicit `Tmpfs=`, `NoNewPrivileges=true`, `PidsLimit=`, default seccomp
   (never `SeccompProfile=unconfined`), no `--privileged`, no host PID, no
   `/dev` passthrough, and `SELinux` left enforcing. For the *untrusted* case,
   a VM with a narrow virtiofs share replaces all of it.
7. **Management plane off the data path** — Syncthing's GUI and Transmission's
   RPC are administration interfaces. After step 5 they are no longer on the
   host's loopback, so "bind it to `127.0.0.1`" has to be said in netns terms:
   publish the port on the host's loopback only
   (`PublishPort=127.0.0.1:8384:8384`, which netavark or rootlessport DNATs into
   the container) and reach it over an SSH tunnel, or bind the process to the
   workload's VLAN address and firewall that port to the management VLAN.
   Publishing `8384:8384` or `9091:9091` on every interface is the failure mode
   to avoid — and it is the state a `Network=host` unit is already in, where the
   UI listens wherever the application binds.

A per-workload slice and a per-workload netns together are the smallest change
that makes "the isolation of this workload" a property of the system rather
than of the container's configuration.

## How far an escape is from host root

The privilege an RCE must cross depends entirely on how the container was
started, and the uid shape only decides how much is left standing after the
first crossing.

| start mode | escape yields | remaining work for root |
| --- | --- | --- |
| `--privileged`, `--pid=host`, `/dev` or the podman socket mounted, rootful Podman | host root directly | none — the container *is* a root shell |
| rootful Podman, default | host root inside the container's namespaces; a kernel escape is needed for the host | one kernel bug; `container_t`/MCS still confine after it |
| rootless Podman, default userns | the mapping's target: a subuid for container root, the host uid for `keep-id` | a user-namespace/kernel escape, then a *local privilege escalation* as an ordinary uid |
| rootless Podman, per-workload uid (the target shape) | that workload's host uid | the same LPE, but the blast radius stops at one workload's data |

So the honest count for the target shape is **two kernel-class crossings** —
one out of the user namespace/container, one from an unprivileged uid to root —
or one crossing plus a userspace misconfiguration (a setuid binary, a polkit
rule, a writable unit file, a `sudo` entry, a docker/podman socket). The second
crossing is the same problem every local user on the host has; what the uid
split changes is that an escaped workload is *no longer* an unprivileged user
with access to the other workloads' state.

What still applies after an escape, and what does not:

- **still applies**: DAC as the mapped uid, SELinux type plus MCS category
  (the domain does not change because the process is uid 0 inside its
  namespace), the cgroup slice's limits, `nodev`/`noexec`/`nosuid` on mounts;
- **no longer applies**: seccomp (the escape means the filter was bypassed),
  capabilities (namespace-scoped), the container's mount namespace, and
  `no-new-privileges` only until the process re-execs a setuid helper it can
  reach.

Host-side knobs that raise the cost of the second crossing without breaking the
workloads: `kernel.io_uring_disabled=2` (a large and recurring LPE surface, and
neither app needs it), `kernel.unprivileged_bpf_disabled=1`, `kernel.kptr_restrict=2`,
`kernel.dmesg_restrict=1`, `kernel.perf_event_paranoid=3`,
`kernel.yama.ptrace_scope=1`, `vm.mmap_min_addr=65536`. Do **not** set
`kernel.unprivileged_userns_clone=0`: it would remove the rootless Podman
boundary this whole shape depends on.

The one thing this analysis cannot fix: with `Network=host`, an escaped
workload is already a peer of the host's loopback services, and with a
`--privileged` container there is no boundary to discuss. Those are
configuration choices, not kernel properties.

## Wide-area connectivity

Both applications ask the router for an inbound port, but only over a narrow
set of protocols, and every one of them is a discovery protocol first:

- **Syncthing** tries UPnP-IGD (SSDP `M-SEARCH` to `239.255.255.250:1900`, then
  SOAP to the IGD's HTTP port) and NAT-PMP (UDP 5351 to the default gateway),
  per device, and shows the result per router. Independently of the mapping it
  uses global discovery and public relays, so it still syncs without any
  inbound port — slower, and relayed.
- **Transmission** tries UPnP-IGD and NAT-PMP for its peer port. It has no
  relay: without a mapping it still connects outward, but it is not
  "connectable", which costs peers and speed.

Both need *discovery* to succeed before the mapping is even attempted. That is
the part a network namespace breaks, because SSDP is link-local multicast in
the namespace and NAT-PMP goes to whatever the namespace calls "gateway".

What each network shape does:

| shape | SSDP discovery | NAT-PMP | inbound | notes |
| --- | --- | --- | --- | --- |
| `Network=host` (today) | reaches the LAN | reaches the router | works | all workloads share one client and compete for the same mappings |
| Podman bridge + `-p`/`PublishPort` | no — the bridge does not forward `239.255.255.250` | no — the bridge gateway is not a PMP server | static forward to the host port works, because netavark DNATs it | the app cannot open its own port; the lease is the router's static config |
| `pasta`/`slirp4netns` (rootless default) | no in slirp; pasta's multicast forwarding is limited and version-dependent — test it | no in slirp; pasta depends on `--map-gw` | publish still works via the host | slirp has no ICMP and no multicast, so UPnP is simply out |
| macvlan on a VLAN (rootful) | yes — the container is an L2 peer | yes | works | container cannot reach the host's own IPs on that interface |
| VM with NAT (libvirt default) | no — dnsmasq relays DHCP/DNS, not SSDP | no — the libvirt gateway is not an IGD | static forward to the VM + router forward | double NAT, two forwards to maintain |
| VM with bridged/macvtap NIC | yes | yes | works | a full L2 peer: it can ARP-spoof the host, so it belongs on its own VLAN |
| VLAN sub-interface + macvlan/bridge | yes, within that VLAN | yes, if the router's VLAN interface is reachable | works | the shape that also gives isolation |

### What a netns does to "what is my address"

The two clients are not symmetric here, and the difference decides whether a
netns is neutral:

- **Syncthing describes itself.** It enumerates its own interfaces for LAN
  addresses, asks the router for the external address (UPnP-IGD/NAT-PMP), and
  announces both to global discovery; local discovery broadcasts on its own
  interfaces. In a bridge netns it therefore announces the container's
  `10.88.x.y` — unreachable from the LAN and from the internet — while SSDP does
  not traverse the bridge, so no mapping and no external address either. The
  result is relay-only sync: it works, slower. pasta changes the first half
  (the container gets a copy of the host's addresses, so it announces the host
  LAN address) but not the second (SSDP still does not traverse pasta). Only
  macvlan/VLAN or host networking make its self-description true.
- **Transmission describes nothing.** It binds a peer port and asks the router
  to map it; when that fails it reports "port closed" and connects outward with
  fewer peers. A static `dst-nat` on the router plus a published port restores
  inbound exactly, and `port-forwarding-enabled=false` stops it from wasting
  discovery attempts inside a netns.

Throughput is the second half of the same question: `pasta` is a user-space L4
proxy — comfortably above 1 GbE in practice, at a CPU cost — while
`slirp4netns` is the slow one (single-threaded, ~1 Gbps ceiling). On this host
neither is the bottleneck: two drive-managed SMR members in a Btrfs pool are
slower than any of these transports. Rootless Podman cannot create a host
bridge, so rootless means pasta; full speed means a rootful bridge or macvlan,
which re-opens the "rootful Podman is root" trade.

Two router-side facts follow from the MikroTik and the dumb switch:

- **RouterOS speaks UPnP-IGD, not NAT-PMP/PCP.** `/ip upnp` with `internal`
  set to the relevant interfaces (including any VLAN interface) gives clients
  an IGD to discover; the NAT-PMP half of each client's mapping attempt has
  nothing to answer it. So on this router the mapping path is UPnP-IGD or
  static configuration — the NAT-PMP scripts in `bin/-nat-pmp.py` and
  `bin/-nat-pmp2.py` document the protocol but will time out against RouterOS.
- **SSDP depends on the L2 plumbing.** A dumb switch forwards link-local
  multicast, so discovery works in one flat broadcast domain. It stops working
  as soon as the traffic is split by a VLAN — the router's VLAN interface has
  to carry the workload and be listed in `/ip upnp internal` — or once the
  bridge enables IGMP snooping without a querier, which stops flooding the
  group an IGD search needs. If VLANs and UPnP are both wanted, the VLAN
  interface, not the physical one, must be the UPnP internal interface.

The practical alternatives, best first:

1. **Static lease plus static `dst-nat` per workload.** One DHCP reservation per
   workload address and one `/ip firewall nat` rule per published port, with
   UPnP disabled on both the router and the apps. It is inspectable, it does
   not expire, it does not collide when two workloads want the same external
   port, and it survives the container getting a new bridge address because the
   rule points at the host or the VM, not at the ephemeral container IP.
2. **IPv6 instead of NAT.** `bin/-upkeep-ipv6.sh` already keeps the Hurrican
   Electric 6in4 tunnel endpoint current, which means the router holds a routed
   prefix. Give each VLAN a prefix from it and open firewall pinholes per
   workload: no NAT, no UPnP, no mapping collisions, and each workload gets a
   stable global address. Both applications speak IPv6. This is the only shape
   that is both *more* isolated and *more* connectable.
3. **macvlan on a workload VLAN** when a workload genuinely needs an L2
   presence (or a bridged VM NIC). It restores UPnP, at the price of the
   workload being an L2 peer and of the host↔container macvlan isolation.
4. **Host networking** only where the workload is trusted and there is exactly
   one of it; it is what breaks both the netns isolation and the mapping
   competition.

Recommendation per workload: Syncthing does not need inbound at all (relays plus
discovery), so it can move to a private netns with no published port and no
UPnP; Transmission keeps one static UDP/TCP port with a `dst-nat` rule and UPnP
disabled; `hister-nogon` publishes 4433 and has no peer-to-peer need, so it
gets the same static mapping (or an IPv6 pinhole) and never uses UPnP.

## Mixing host, container and VM traffic

On one flat L2 domain, "mixing" is not a bandwidth problem, it is a trust
problem: every bridged VM and every macvlan container is a full L2 peer of the
host and can ARP-spoof it, answer mDNS/LLMNR, or run a DHCP server. Netns
containers behind a bridge are not L2 peers, so the risk is concentrated in the
bridged/macvlan shapes.

Segmenting on this hardware is cheap because only the two managed ends need
configuration: tag VLANs on host sub-interfaces (e.g. `eno1.20`), configure the
matching VLAN interfaces and per-VLAN DHCP/firewall on the RouterOS bridge, and
let the dumb switch forward the tags. A workable split:

| VLAN | members | why |
| --- | --- | --- |
| native/untrusted-tagged | host management, router | the host itself |
| workload | netns containers behind a bridge, or macvlan peers | untrusted-ish services, no L2 access to the host |
| VM | bridged/macvtap VM NICs | full L2 peers, isolated from the host and the workloads |

If a VM is NATed instead of bridged, it needs no VLAN at all — but then it also
gets no UPnP and needs the double static forward.

## Open questions

- Whether the three workloads keep uid 1000 for a transition period, or move to
  per-workload uids in one step (the data ownership migration is the cost).
- Whether the pool host needs to reach the workloads at all after the move to
  netns networking (health checks, upkeep scraping); macvlan makes that
  one-way.
- Whether RouterOS on the hEX E50UG has IGMP snooping enabled on the bridge,
  and whether `/ip upnp internal` currently names the physical interface.
- Whether the 6in4 prefix is a /64 (one VLAN) or a /48 (prefix per VLAN).
- Whether `hister-nogon` has a health endpoint and a defined stop budget; the
  new unit currently has neither.

## Non-goals

- No user, subuid line, slice, VLAN, firewall rule or Quadlet option is
  installed by this note.
- No claim that a per-workload uid stops a kernel exploit; it bounds the
  damage, it does not prevent the crossing.
- No UPnP or NAT-PMP configuration is recommended as a deployment default.
