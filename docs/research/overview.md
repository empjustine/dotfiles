---
id: research-overview
type: architecture-design
status: draft
title: "Dotfiles — prior-art research: declarative upkeep"
parent: index
references: [index, design, decision-log, research-guards, research-files-volumes, research-upkeep-mapping]
---

# Dotfiles — prior-art research: declarative upkeep

This is a draft research note, not a decision record and not a migration plan.
It records the prior art examined for the next step of the upkeep allocator
(DR-049, DR-051, DR-052, DR-053), and maps it onto the current manifest and
scripts. Nothing in the tree is expected to obey it yet; the status is
`draft` so a later decision can cite it without rewriting it.

The companion documents are [guards and steps](guards-and-steps.md),
[files and volumes](files-and-volumes.md), and
[the upkeep mapping](upkeep-mapping.md). The current system is described in
[the systems reference](../system.md) and [the design](../design.md); the dated
record log is [DECISIONS.md](../../DECISIONS.md).

## Scope

The research answers four questions that came out of the last rounds of upkeep
work:

1. Is a generic `ConditionExecIf` / `ConditionExecUnless` the right way to
   express the remaining shell guards, or are typed file, host and container
   checks the better prior-art match?
2. Should host directories and cleanup be expressed with `tmpfiles.d`, and
   what does a non-systemd host do?
3. Can the container and volume handling be expressed with Podman's
   Kubernetes-shaped volumes and Quadlet instead of one-off scripts, including
   storage outside the home directory?
4. Is a `(string[])[]` step list justified, and what should its semantics be?

A fifth, practical question runs through all four: **what can be reused
instead of built?**

## Method and verification

The primary sources are the bare checkouts under `~/Downloads/references/`.
Claims marked as verified were read in those trees at the commits below.
Package names for non-systemd tmpfiles providers are external corroboration,
not present in these checkouts; they are labelled where they appear.

| source | revision read | used for |
| --- | --- | --- |
| `systemd/systemd.git` | `054ca239`, 2026-11-20 | unit conditions/asserts, `ExecCondition`, `tmpfiles.d`, `RuntimeDirectory`, `Type=oneshot` |
| `podman-container-tools/podman.git` | `19c75a78`, 2026-11-20 | `podman kube play`, PVC annotations, Quadlet generators, local volume driver, auto-update |
| `kubernetes/kubernetes.git` | `539fda3e`, 2026-11-20 | PVC/PV/StorageClass API fields, StatefulSet retention, local volumes |
| `kubernetes/website.git` | checkout of 2026-11-20 | storage concepts: access modes, reclaim, binding, ephemeral volumes |
| `kubernetes-sigs/kind.git` | checkout of 2026-11-20 | the minimal local-path provisioner manifest |
| `openebs/mayastor.git` | `e2668a42`, 2026-11-20 | the replicated/CSI end of the volume spectrum |
| `compose-spec/compose-spec.git` | `6b3a2a93`, 2026-11-17 | `driver_opts` and `external` volume vocabulary |
| `F1bonacc1/process-compose.git` | `190d0262`, 2026-11-18 | dependency conditions, readiness/liveness probes, restart policy |
| `jdx/mise.git` | checkout of 2026-11-20 | `skip_if`, `sources`/`outputs`, `run` arrays, lock slots |
| `dhall-lang/dhall-lang.git` | `56b0997a`, 2026-08-29 | typed, total configuration generation |
| `pulumi/docs.git` | `db27a81e`, 2026-11-20 | preview/import/state as a reconciler model |

The external notes on OpenRC, Gentoo `systemd-utils`, `seedfiles` and
`opentmpfiles` come from a DeepWiki query, not from the checkouts. They are
useful pointers but must be verified on the target distribution before being
treated as a dependency.

## Findings in one page

- Typed conditions and asserts are the systemd model; a generic exec predicate
  is the escape hatch, not the primary mechanism. Condition-skip is a
  successful job (systemd `JOB_DONE`); assert-failure is a failed job
  (`JOB_ASSERT`). A skip must count as done, release tokens, consume no retry,
  and still satisfy dependents.
- The current one-off scripts are mostly **composites**, not predicates. Of the
  16 conditionals in the nine `script` jobs, 10 are internal resets or fallback
  choices between verbs and only 6 are job-level guards. Most of those 6 are
  workarounds for non-idempotent verbs, which idempotent flags remove without
  any condition language.
- `tmpfiles.d` is a portable file format with several implementations.
  `systemd-tmpfiles` itself is standalone; it needs `/proc` and is split into
  `systemd-utils` on non-systemd distributions. It creates directories, files,
  links, nodes and copies, but it does **not** mount and is not a multi-line
  config deployer.
- Podman already has a PVC-shaped volume: a Kubernetes `PersistentVolumeClaim`
  becomes a named Podman volume, with `volume.podman.io/*` annotations for
  device, type, mount options, driver, uid/gid. Quadlet generates the same
  thing as a systemd oneshot, with `podman volume create --ignore`.
- A Quadlet volume can live on the external disk: `Device=` plus
  `Type=bind` bind-mounts the external directory onto the volume's mountpoint.
  The volume object and mountpoint stay in Podman's graphroot (small); the data
  is on the external disk. Use `Type=bind`, not `Options=bind`, to get device
  validation and a `RequiresMountsFor=` edge.
- Quadlet containers recover from common improper state by construction:
  `podman run --name … --replace --rm`, `ExecStop`/`ExecStopPost` with
  `podman rm -v -f -i`, and `KillMode=mixed`. Volumes recover only partially:
  creation is idempotent, options are immutable, and a wrong volume needs an
  explicit remove/recreate.
- Controlled shutdown is a systemd ordering property. The container stops
  before its volume and its mount only when the external disk is a
  systemd-known mount. An udisks-mounted disk has no `.mount` unit, so
  `RequiresMountsFor=` has nothing to order against; use fstab automation, a
  `.mount`/`.automount` unit, or `systemd-mount`.
- `(string[])[]` is well-precedented: systemd `Type=oneshot` with repeated
  `ExecStart=` and mise's `run` array both run serially and stop at the first
  failure. systemd adds a per-command `-` ignore-failure prefix and applies one
  timeout to the whole activation. Upkeep should mirror those choices and keep
  one executor per job.

## Document set

| document | what it holds |
| --- | --- |
| [guards and steps](guards-and-steps.md) | conditions, asserts, exec predicates, and command-sequence prior art |
| [files and volumes](files-and-volumes.md) | `tmpfiles.d`, Kubernetes PVCs, Podman PVC-shaped volumes, Quadlet, out-of-home storage and recovery |
| [upkeep mapping](upkeep-mapping.md) | the concrete mapping, proposed schemas, reuse/build lists, pitfalls and validation |
| [pool audit](quadronegro-at-home-audit.md) | verified findings for the Btrfs RAID1, Infisical and udisks setup under `~/unraid-at-home/`; includes the single-filesystem correction |
| [pool design](quadronegro-at-home-design.md) | candidate secret, mount, Quadlet and shutdown design derived from that audit |

## Status

Draft. The research is complete enough to support a decision, but no choice has
been made. A future DR would need to pick:

- whether the manifest gets a `steps` field, and whether remote jobs get steps
  or keep a single `script`;
- whether upkeep owns a volume schema or delegates volumes entirely to Quadlet
  and `podman kube play`;
- whether a non-systemd host is ever a target that needs a tmpfiles subset;
- whether any exec predicate is retained, and with which exit-code contract;
- whether the quadronegro lifecycle moves to system units and the allocator gains
  credentials, steps and asserts, or stays script-wrapped (see the
  [pool audit](quadronegro-at-home-audit.md),
  [pool design](quadronegro-at-home-design.md) and
  [availability register](quadronegro-availability-and-threats.md)).

## What this is not

It is not a claim that all nine scripts should disappear. The mapping document
concludes that three of the nine are removable immediately (Quadlet and
idempotent flags), two more once a remote step runner exists, and that the
remaining four (move/compress, generator, pipeline, and a genuine state
comparison) should stay scripts. It is also not a portability
promise: every mechanism named here has a systemd, Podman, or distribution
dependency that has to be checked on the target host.
