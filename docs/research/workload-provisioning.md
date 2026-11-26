---
id: research-workload-provisioning
type: architecture-design
status: draft
title: "Declarative workload provisioning: from a declaration to units, uids and mountpoints"
parent: index
references: [index, research-multi-uid-access, research-workload-isolation-egress, research-quadronegro-design, research-quadronegro-availability-threats, research-guards, declarative-upkeep-poc, system, decision-log]
---

# Declarative workload provisioning

This note sketches what it takes to stop creating mountpoints, uids and user
units by hand (or by an agent typing them one command at a time) and instead
declare a workload once and let an idempotent materialiser produce every piece:
the host identity, the subid range, the linger marker, the data directories with
their ownership and label, the cgroup slice, the Quadlet volume and container,
the network attachment, the pool membership and the assertions that prove it.
It is a design sketch with a worked `promnesia` example, not an installed
change.

The companion documents are [multi-uid access](multi-uid-data-access.md), which
owns the uid/ACL/bind-mount detail, [workload isolation and
egress](workload-isolation-and-egress.md), which owns the netns/VLAN/UPnP
detail, [the pool design](quadronegro-at-home-design.md) and [its availability
register](quadronegro-availability-and-threats.md), and [the declarative upkeep
proof of concept](../declarative-upkeep.md), which owns the job schema.

## What is manual today

Three artefacts per workload are written by hand right now:

| artefact | written by | where it lives now |
| --- | --- | --- |
| host identity, subids, linger | nobody yet — every workload runs as uid 1000 | `docs/research/multi-uid-data-access.md` proposes the sysusers shape |
| data directory, ownership, label | implicitly, by `:U` on the container mount | chowned to a subuid on every start |
| Quadlet volume + container | hand-written INI | `config/quadlet/*.volume`, `*.container` |
| pool membership, netns, ports | hand-written, inconsistently | `Network=host` for two, `PublishPort=` for one |

The examples are "not installed" on purpose, and nothing reconciles them with
what is on the host. That is the gap: a new workload (say `promnesia`) means an
agent typing `sysusers.d` lines, `tmpfiles.d` lines, a Quadlet pair, a slice, a
VLAN attachment and a manifest job, and hoping the six agree.

## The shape of the answer

Three new artefacts, and a rule about who applies what:

1. **One workload declaration** per workload — a JSON document validated the
   way the allocator validates a manifest (unknown fields are errors, not
   warnings).
2. **A renderer/materialiser** with four verbs: `plan` (render to text or a
   diff), `apply` (write + run the idempotent executors), `verify` (run the
   declaration's assertions), `retire` (stop, disable, keep the data).
3. **A uid/subid ledger** — the only genuinely stateful piece, because
   numbers must not be reused and must not collide.

And one rule: **the materialiser does not invent state, it renders files that
systemd already knows how to apply idempotently.** Nearly every piece of a
workload is a systemd-native declarative artefact whose executor is built in:

| declaration field | rendered artefact | executor (idempotent) | privilege domain |
| --- | --- | --- | --- |
| `uid`, `group` | `/etc/sysusers.d/quadronegro-<name>.conf` | `systemd-sysusers` | root |
| `subid` | `/etc/subuid`, `/etc/subgid` lines | none upstream — a managed append step | root |
| linger | `/var/lib/systemd/linger/<name>` (empty file) | `systemd-tmpfiles --create` | root |
| data dirs, modes, labels, ACLs | `/etc/tmpfiles.d/quadronegro-<name>.conf` (`d`, `Z`, `a`) | `systemd-tmpfiles --create` | root |
| mountpoints (pool and per-workload) | the same tmpfiles file, plus a `.mount` when the workload has its own volume | `systemd-tmpfiles`, `systemctl` | root |
| slice and limits | `<name>.slice` with `Delegate=yes` | `systemctl daemon-reload` | root |
| Quadlet volume + container | `~<name>/.config/containers/systemd/*.volume`, `*.container` | `systemctl --user daemon-reload`, `start` | the workload uid |
| pool membership | `RequiresMountsFor=`, `PartOf=`, `WantedBy=` inside the generated `.container` | the same user manager | the workload uid |
| network attachment | Quadlet `Network=`/`PublishPort=`, or a NetworkManager keyfile / networkd `.netdev` for a VLAN | `systemctl --user` or `systemctl` | both |
| secrets | `/etc/credstore.encrypted/<name>` + `LoadCredentialEncrypted=` drop-in | `systemd-creds encrypt` once | root |
| backup class | a label consumed by the backup job generator | the allocator | root |

The important consequence: the materialiser is mostly a **renderer**. The
imperative part is small and bounded — subid allocation, the file write with a
generated-file header, and the ordering between the two privilege domains.

## Two privilege domains, one applier

The pieces belong to two systemd managers, so `apply` is a two-phase, ordered
protocol — but both phases can be driven by **one root-side process**, which is
the smaller design:

1. **system phase (root)**: sysusers, subid lines, linger marker, tmpfiles
   (directories, ownership, labels, mountpoints, ACLs), slice unit,
   VLAN/firewall, credentials, plus `systemctl daemon-reload` and
   `systemd-sysusers`/`systemd-tmpfiles --create`.
2. **workload phase (that uid's manager)**: write the Quadlet files *owned by
   the uid*, then `systemctl --user --machine=<name>@.host daemon-reload` and
   `start` — root talks to the workload's manager over D-Bus, so no shell, no
   login and no `nologin` problem. `machinectl shell` and `runuser`/`setpriv`
   are the fallbacks for anything that is not a `systemctl` call.

Three constraints fall out of the impersonation route:

- `enable-linger` must land **before** the user phase, or `--machine=<name>@.host`
  has no manager to talk to. That is why linger is a tmpfiles marker file
  (`/var/lib/systemd/linger/<name>`) rather than a `loginctl` call: it is
  declarative, and it is applied in the system phase by construction.
- Files written by root into the workload's Quadlet directory must end up with
  the right SELinux context, or the user manager cannot read them; the same
  tmpfiles `Z`/`z` line that labels the data directory covers
  `/var/lib/workloads/<name>`.
- The *runtime* stays rootless in that user's manager (that is what keeps the
  uid/userns boundary); only the *application* is privileged. A rootful Quadlet
  with `User=` would apply as root and run as root — the opposite.

The order matters, and teardown reverses it: identity → directories → linger →
user manager → units → writers → mount → mappings. A system-phase failure
aborts before the workload phase runs, which is the allocator's `steps`
semantics (serial, stop at first failure), so the job shape can be either one
job with two steps or two `after`-chained jobs:

```json
{"name": "workload-promnesia", "phase": "maintenance",
 "steps": [["./bin/workload-apply", "apply", "--phase", "system", "config/workloads/promnesia.json"],
           ["./bin/workload-apply", "apply", "--phase", "user",   "config/workloads/promnesia.json"]]}
```

and for the pool lifecycle, the workload unit joins the state target
(`PartOf=`/`WantedBy=quadronegro-pool.target`) rather than an `after` edge.

## The declaration

JSON, because the allocator already parses and strictly validates JSON, and a
second schema language would double the gates. One file per workload:

```json
{
  "name": "promnesia",
  "uid": 10204,
  "subid": "auto",
  "data": {
    "private": "workloads/promnesia",
    "read_only": ["media", "imports/browser-history"]
  },
  "unit": {
    "image": "localhost/promnesia:latest",
    "exec": ["promnesia", "serve", "--host", "127.0.0.1", "--port", "1313"],
    "ports": ["127.0.0.1:1313:1313"],
    "volumes": [{"data": "private", "mount": "/promnesia/data"}],
    "network": "loopback",
    "capabilities": [],
    "read_only_rootfs": true,
    "health": {"cmd": ["cmd", "curl", "-fsS", "http://127.0.0.1:1313/"], "stop_timeout": 30}
  },
  "slice": {"cpu_weight": 100, "memory_max": "2G", "tasks_max": 256},
  "pool": {"target": "quadronegro-pool.target"},
  "retain": true
}
```

What each field means, and the non-obvious ones:

- `subid: "auto"` makes the ledger pick the next 65536 block; a literal is
  accepted for a workload that must keep a range.
- `data.private` is the only writable tree; `data.read_only` are bind views, so
  the read-only property is a kernel mount, not a promise.
- `unit.network` is an enum (`host`, `loopback`, `bridge`, `macvlan:<vlan>`),
  because "host networking for one of them" is a decision that must be visible
  in the declaration, not implied by a missing option. It also carries the
  discovery requirement: a client that announces its own addresses (Syncthing)
  is broken by `bridge` and only works with `host`, `pasta` or
  `macvlan:<vlan>`, so `plan` should warn when a self-describing client asks for
  a shape that hides its address (see [isolation and
  egress](workload-isolation-and-egress.md)).
- `pool.target` is the state target the workload joins (`PartOf=`), which is
  what makes "stop the pool, stop its writers" true for a workload added later.
- `retain` is the reclaim policy, defaulting to true — the materialiser never
  deletes data, matching the Quadlet `retain` stance.

Rejected on purpose, because the existing notes already concluded them: a
volume schema (Quadlet owns volumes), a network schema beyond the enum, a
`DynamicUser=yes` mode (a workload that owns persistent data needs a stable
uid), and any `chown -R` of a shared tree.

## Worked example: promnesia

Assuming the documented defaults — `promnesia serve` on port 1313, a SQLite
cache/DB under a data directory, and browser-history exports produced elsewhere
— the declaration above renders:

```
/etc/sysusers.d/quadronegro-promnesia.conf
  u promnesia 10204 "promnesia workload" /var/lib/workloads/promnesia /usr/sbin/nologin

/etc/subuid, /etc/subgid        (managed block, one line per workload)
  promnesia:524288:65536

/var/lib/systemd/linger/promnesia          (empty file, 0644)

/etc/tmpfiles.d/quadronegro-promnesia.conf
  d /var/mnt/quadronegro/workloads/promnesia 2770 promnesia promnesia -
  Z /var/mnt/quadronegro/workloads/promnesia -    promnesia promnesia -
  d /var/lib/workloads/promnesia             0700 promnesia promnesia -

/etc/systemd/system/promnesia.slice
  [Unit] Description=promnesia workload slice
  [Slice] CPUWeight=100 MemoryMax=2G TasksMax=256

~promnesia/.config/containers/systemd/promnesia-data.volume
  [Volume] VolumeName=promnesia-volume Driver=local
  Device=/var/mnt/quadronegro/workloads/promnesia Type=bind Copy=false

~promnesia/.config/containers/systemd/promnesia.container
  [Unit]
  RequiresMountsFor=/var/mnt/quadronegro
  PartOf=quadronegro-pool.target
  [Container]
  ContainerName=promnesia
  Image=localhost/promnesia:latest
  UserNS=keep-id
  PublishPort=127.0.0.1:1313:1313
  Volume=promnesia-data.volume:/promnesia/data:Z
  Volume=/var/mnt/quadronegro/media:/media:ro,z
  ReadOnly=true
  DropCapability=all
  NoNewPrivileges=true
  StopTimeout=30
  Exec=promnesia serve --host 127.0.0.1 --port 1313
  [Install]
  WantedBy=quadronegro-pool.target
```

Notes that the renderer must encode rather than hope for:

- `UserNS=keep-id` (not `U`): the container user maps to uid 10204, so files
  stay owned by the workload instead of a subuid.
- `:Z` only on the private directory; `:ro,z` on shared media. `:U` is never
  rendered.
- `PublishPort=127.0.0.1:…` because a personal web UI is a management surface:
  loopback plus an SSH tunnel, not a LAN port and never UPnP.
- `PartOf=` and `WantedBy=` both, because `WantedBy=` alone leaves the
  container running when the pool target stops.
- `ReadOnly=true` with `DropCapability=all`, which promnesia (a static web app
  over a SQLite file) does not need to defeat.

Assertions for the workload, in the allocator's kind vocabulary plus three new
kinds that this flow needs:

```json
[{"user_exists": "promnesia"},
 {"subid_present": "promnesia"},
 {"path_exists": "/var/lib/systemd/linger/promnesia"},
 {"path_is_dir": "/var/mnt/quadronegro/workloads/promnesia"},
 {"path_is_mount_point": "/var/mnt/quadronegro"},
 {"unit_active": "promnesia.service"},
 {"port_bound_on": "127.0.0.1:1313"},
 {"file_contains": ["/var/mnt/quadronegro/workloads/promnesia/.owner", "10204"]}]
```

`user_exists`, `subid_present`, `unit_active`, `port_bound_on` and
`file_contains` are new; the existing set (`path_exists`, `path_is_dir`,
`path_is_mount_point`, `command_exists`, `block_device_exists`,
`credential_present`, `env_present`) covers the rest. They are deliberately
small, per [guards and steps](guards-and-steps.md): an idempotent verb beats a
probe.

## What has to be built, and what must not be

Build:

1. `bin/workload-apply` (or a `render` field in the allocator) with
   `plan|apply|verify|retire`, `--phase system|user`, and a strict schema.
2. A uid/subid ledger — a JSON file with the assigned numbers, checked for
   collisions and never decremented. `subid: "auto"` reads it; a literal
   updates it.
3. The five assert kinds above, in `bin/upkeep_asserts.py`.
4. A fixture test in `tests/`: the three existing Quadlet pairs
   (`syncthing`, `transmission`, `hister`) become the *golden render output*.
   `plan` must reproduce them byte-for-byte from declarations, which turns
   today's "uninstalled examples" into a regression test instead of prose.
5. A generated-file header on everything written, so `plan` can detect drift
   and `apply` can refuse to overwrite a hand-edited file without `--force`.

Do not build:

- a volume or network schema (Quadlet and NetworkManager/networkd own them);
- a process supervisor (systemd owns it; the allocator only schedules);
- a recursive chown or relabel step for shared trees;
- a delete path that removes data (`retire` stops, disables, keeps);
- a second DAG: the allocator keeps scheduling, the renderer only renders.

## Why this is worth it

Three properties change once a workload is a declaration:

- **Reviewability**: a new workload is one diff — uid, data, ports, limits,
  pool membership, assertions — instead of six files in four directories.
- **Drift detection**: `plan` diffs rendered output against the host, so "the
  Quadlet file that was hand-edited in March" is a finding, not folklore.
- **Teardown**: `retire` is the reverse render, so a workload leaves no linger
  marker, no subid block and no orphan slice behind.

## Open questions

- Whether `workload-apply` is a new binary or a `render` job field in the
  allocator; the allocator's own note argues for keeping it a scheduler, so a
  binary plus two jobs is the smaller step.
- Whether the ledger is a checked-in JSON file (reviewable, but every
  allocation is a commit) or derived deterministically from the name (no state,
  but collisions and renames are painful).
- Whether the VLAN attachment is NetworkManager keyfiles or systemd-networkd;
  on Bazzite the NetworkManager path needs no extra package.
- Whether per-workload credentials are rendered or left to a provisioning job,
  because the secret must come from somewhere the renderer should not know.
- Whether `promnesia` should have a port at all, or be reverse-proxied like the
  existing `llm-reverse-proxy`.

## Non-goals

- No script, unit or user is created by this note.
- No claim that a declaration makes a workload safe; it makes it reproducible.
  Isolation quality is still the uid/slice/netns/MAC choices above.
- No commitment to promnesia's actual CLI or port; the declaration is where
  that assumption is recorded and becomes testable.
