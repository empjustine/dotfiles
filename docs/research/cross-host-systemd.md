---
id: research-cross-host-systemd
type: architecture-design
status: draft
title: "Cross-host systemd and distributed management"
parent: index
references: [index, research-overview, research-upkeep-mapping, research-multi-uid-access, research-termux-orchestration, decision-log]
---

# Cross-host systemd and distributed management

This note answers a narrow question: is there an upstream, cross-host systemd
that turns a set of machines into a cluster the way a Kubernetes control plane
plus kubelets does? The short answer is **no**. systemd is a per-host manager;
its remote facilities are per-host SSH, log forwarding and local container/VM
registration. The closest true cluster-level systemd scheduler was CoreOS
**fleet**, which was deprecated in 2018 in favour of Kubernetes. That history is
useful because it shows both what a distributed systemd looks like and why it
was not maintained.

## What systemd provides, and what it does not

| capability | mechanism | scope |
| --- | --- | --- |
| local service manager | `systemd` as PID 1 plus the local D-Bus API | one host |
| remote operation | `systemctl --host=user@host` / `-H`, which uses SSH to reach the remote machine manager | one host per invocation; no shared state, no scheduling |
| local containers and VMs | `systemd-machined`, `machinectl`, `systemd-nspawn` | one host |
| portable services | `systemd-portabled` / `portablectl` | one host or one user manager |
| log aggregation | `systemd-journal-remote`, `systemd-journal-upload`, `systemd-journal-gatewayd` | logs only, not control |
| timers and cgroup hierarchy | local units, slices and scopes | one host |

There is no cluster membership, leader election, desired-state store, scheduler,
API server, node agent, rolling update or RBAC in systemd. The local-bus design
is deliberate: the 2015 systemd-devel thread that asked for a remote API was
answered with "use a separate daemon", and the current `--host` path is SSH, not
a network control plane. The journal services aggregate logs; they do not
schedule work.

The practical consequence is that "distributed systemd" is either:

1. a set of independent hosts driven by SSH, a configuration manager or a
   deployment tool; or
2. a separate cluster scheduler that uses systemd as the local execution agent.

## Prior art

| system | model | systemd units as the unit of work? | status and lesson |
| --- | --- | --- | --- |
| **CoreOS fleet** | every host runs `fleetd` with an *engine* and an *agent*; etcd is the sole datastore; engines take a lease and reconcile desired state against current state; agents talk to local systemd over D-Bus; `fleetctl` is the client | yes — it schedules service, socket, path and timer units, with `[X-Fleet]` placement constraints | the closest direct prior art. Deprecated after 2018-02-01 and replaced by Kubernetes. It had no ACLs (etcd access was cluster control), no resource-aware scheduling, no rolling updates, and was not recommended above ~100 nodes or ~1,000 services |
| **Kubernetes** | API server, etcd, scheduler and controller-manager form the control plane; kubelet runs on each node and manages pods | no — pods, not systemd units; kubelet can use the systemd cgroup driver (`--cgroup-driver=systemd`) and can read static pod manifests | the system that displaced fleet. It is the right choice if the requirement is a real cluster control plane, but it is far more machinery than a single-owner DAG needs |
| **k3s / k0s** | a single binary that runs the control plane and the node agent; a server can also be a worker, and agents join | no — Kubernetes objects | useful for the "single node versus cluster" analogy: even "single node" still contains a control plane plus a kubelet, not a systemd-only host |
| **Nomad** | servers and clients, with task drivers such as exec, container, QEMU and raw exec | no — Nomad jobs, not systemd units | a lighter scheduler than Kubernetes, but still a separate control plane; not a systemd cluster |
| **mgmt** | a distributed configuration graph with remote execution and convergence | no — resource graph, not unit scheduling | prior art for the agent/convergence model, not for scheduling systemd units |
| **Ansible, Salt, Puppet, Chef** | remote execution and configuration convergence | they can manage unit files, but do not schedule a runtime DAG | the right layer for "make host state match a declaration", not for "run this job now under these resources" |
| **single-host gateways** | e.g. `systemd-pilot`, `systemctl-tui --host`, `terraform-provider-systemd`, `systemd-gateway`, `ssd` | they control units on one host over SSH or a REST bridge | convenient administration, but no cluster state, leader election or scheduling |

Fleet is the answer to "was there a cross-host systemd?". It was real, it worked
at small scale, and it is gone. The replacement was not a better systemd; it was
Kubernetes.

## The single-node versus cluster analogy

A single-node Kubernetes install (`k3s server`, `k0s server`, a `kubeadm`
control-plane on one host) still has the full control-plane/node split: an API
server and a kubelet, usually in one process or one host. Adding an agent joins
another node to the same desired state.

systemd has only the node half. `systemctl --host` is remote *execution*, not a
control plane: each invocation opens SSH, talks to that host's manager, and
returns. There is no object store, no scheduler that sees all hosts, no
reconciliation loop across machines, and no agent registration. `systemd-machined`
registers local containers and VMs, not remote hosts. `systemd-portabled`
attaches an image to one manager.

Fleet filled that gap by pairing an etcd-backed engine with systemd agents. It
was a separate project, not an upstream systemd feature, and it was retired when
Kubernetes became the answer.

## What this means for the upkeep spike

The current allocator is a **single-owner DAG scheduler**, not a kubelet. Its
`hosts:` fan-out and one-SSH-per-job transport are the right shape for a small,
explicit set of maintenance jobs; the research already keeps one connection per
job and forbids one connection per step. Nothing in the manifest needs a
cluster-wide desired-state store.

The useful conclusions are:

- do not build a fleet clone. A leader lease, an etcd store, a scheduler and an
  agent protocol are a control plane; if that is ever needed, use Kubernetes or
  Nomad and let systemd be the local execution layer;
- keep cross-host work as SSH fan-out with declared host tokens. It is
  inspection and maintenance, not distributed state;
- keep the host-local parts host-local: the unraid unlock/mount/shutdown chain
  belongs to one machine, and NFS/SFTP share data, not control;
- if a real cluster is adopted, the interface is a Kubernetes object or a Nomad
  job, not a manifest field in this allocator. The allocator can remain the
  local maintenance DAG beside it.

The Termux host filter in [the Termux note](termux-orchestration.md) reinforces
the same boundary from the other end: the scheduler core is host-neutral, the
systemd executor and container/volume vocabulary are not available there, and
cross-host work reduces to SSH fan-out. A distributed control plane would make
that worse, not better.

## Sources

- `coreos/fleet` README and `Documentation/architecture.md`, `Documentation/fleet-k8s-compared.md`, read 2026-11-25. The README states the 2018-02-01
  deprecation and the Kubernetes recommendation; the architecture document
  describes the fleetd engine/agent split, the etcd datastore, the engine lease
  and the least-loaded scheduler.
- systemd source at `054ca239` (2026-11-20): `man/user-system-options.xml`
  (`--host` uses SSH), `man/systemd-machined.service.xml` (local machines),
  `man/systemd-portabled.service.xml` (local attach), and the
  `systemd-journal-remote`/`-upload`/`-gatewayd` units.
- systemd-devel, "Remote api for systemd via separate daemon", 2015-02-28:
  <https://lists.freedesktop.org/archives/systemd-devel/2015-February/028873.html>.
- Kubernetes source at `539fda3e` (2026-11-20):
  `cmd/kubelet/app/options/options.go` documents `--cgroup-driver=systemd`;
  the kubelet config types document static pod manifests.
- `k3s` at `647ad670` (2026-11-19) and `k0s` at `9f425de4` (2026-11-20) for
  the single-binary server/agent model.
- `mgmt` remote execution note, 2016-10-07:
  <https://purpleidea.com/blog/2016/10/07/remote-execution-in-mgmt/>.

## Open decisions

- Whether the upkeep spike needs any cross-host scheduling beyond `hosts:`
  fan-out; the evidence says no for a single owner and a handful of hosts.
- Whether a future multi-owner setup should be a Kubernetes CronJob/Job, a
  Nomad job, or a small external scheduler that calls the existing allocator.
- Whether to retain fleet as a historical reference only, or to study its
  `[X-Fleet]` placement constraints as prior art for manifest host selection.
