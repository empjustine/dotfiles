---
id: research-upkeep-mapping
type: architecture-design
status: draft
title: "Dotfiles — prior-art research: upkeep mapping"
parent: index
references: [index, system, design, execution-map, decision-log, research-overview, research-guards, research-files-volumes]
---

# Dotfiles — prior-art research: upkeep mapping

This document turns the research into a concrete map of the current upkeep
manifest and scripts: what can be replaced by Quadlet, idempotent flags and
steps, what should remain a script, and which parts of the research are safe to
reuse without building a new subsystem. It is a draft; no schema below has been
accepted, and no file under `config/upkeep/` or `bin/` has been changed for it.

## Current shape

`config/upkeep/jobs.json` has nine `script` jobs. The guard audit in
[guards and steps](guards-and-steps.md) counts 16 conditionals: 10 internal
resets or fallback choices, 4 job-level asserts, 1 job-level skip, and 1 genuine
"only if wrong" comparison. Six of the internal guards are workarounds for
non-idempotent verbs.

| script job | blockers | reuse | outcome |
| --- | --- | --- | --- |
| `upkeep-local/podman-build.sh` | 2 existence guards, 3 verbs | idempotent flags + 3 steps | script removed |
| `-start-syncthing.sh` | container/volume reset, health, root fallback | Quadlet `.volume` + `.container` | script removed |
| `-start-transmission.sh` | health skip, container/volume reset | Quadlet `.volume` + `.container` | script removed |
| `upkeep-remote/oracle-services.sh` | 4 idempotent verbs | remote steps | script removed only when remote steps exist |
| `upkeep-remote/oracle-containers.sh` | 3 idempotent verbs | remote steps | script removed only when remote steps exist |
| `upkeep-remote/oracle-network.sh` | `printf | sudo tee` pipeline | tmpfiles `C` can seed a missing file; steps cannot pipe | script stays |
| `upkeep-remote/oracle-swap.sh` | genuine swap-size comparison | exec condition or script | script stays for now |
| `-upkeep-act-logs.sh` | move + zstd pipeline, computed `xdg-user-dir` | tmpfiles can create/clean dirs; moves stay | script stays |
| `-ssh-upkeep.sh` | jq, heredoc templates, generated files | none | script stays |

With local-only steps, the immediate removals are `podman-build`,
`syncthing` and `transmission` (three of nine). `oracle-services` and
`oracle-containers` become removable once a remote step runner preserves the
current one-SSH-per-job property. The remaining four are composites with real
shell logic: a pipeline, a state comparison, a move/compress job, and a
generator. No declarative file format should absorb those.

## Proposed step schema

Keep `argv` as the single-command form and add a nested form:

    {
      "name": "podman-build",
      "resources": {"disk": 1, "net": 1},
      "after": ["podman-pull"],
      "argv": [
        ["podman", "rmi", "--ignore", "ghcr.io/empjustine/filesynchronization"],
        ["podman", "manifest", "create", "--amend", "ghcr.io/empjustine/filesynchronization"],
        ["podman", "image", "build", "--platform", "linux/amd64",
         "--manifest", "ghcr.io/empjustine/filesynchronization",
         "https://github.com/empjustine/filesynchronization.git"]
      ]
    }

Validation and execution rules:

- Each step is a non-empty argv list; no third nesting level, no shell strings,
  no `sh -c`.
- Steps run serially and stop at the first non-zero exit. The job's exit status
  is that of the failing step.
- One job-level `timeout`, one `retries`, one token set. Do not release tokens
  between steps and do not retry from the middle.
- One executor per job: one transient unit, one tmux pane, one local process.
  A small step runner can be the unit's `ExecStart` and run the argv list with
  signals forwarded to the child process group.
- `plan` prints numbered steps; logs prefix `step N/M`.
- A per-step ignore-failure form is optional. Prefer idempotent flags:
  `podman rmi --ignore`, `podman manifest create --amend`,
  `podman volume create --ignore`, `podman rm --ignore`, `systemctl start`.
  `podman manifest rm --ignore` is the explicit remover if the name currently
  holds a manifest list; `rmi --ignore` mirrors the current script's image
  removal. If a step must be tolerated, use an explicit object step
  (`{"argv": [...], "allow_failure": true}`) rather than a `-` prefix in JSON.
- Remote jobs keep the single `script` transport until a remote runner can run
  the list in one SSH connection. Do not open one SSH per step.

The step list is exactly the systemd `Type=oneshot` repeated-`ExecStart` model,
minus the shell and with JSON's explicit structure instead of the `-` prefix.
It is also the mise `run` array model, minus task references.

## Proposed volume schema

A volume is worth a schema only if upkeep must create it. If Quadlet owns it,
the `.volume` unit is the source of truth and the manifest references the
resulting volume or the container unit. If upkeep must render both backends,
use a small shape like:

    {
      "name": "syncthing",
      "device": "/run/media/deck/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/var/lib/syncthing",
      "type": "bind",
      "mount_options": [],
      "reclaim": "retain",
      "assert_mount": true
    }

Rendering:

| field | Quadlet `.volume` | Podman kube PVC |
| --- | --- | --- |
| `name` | `VolumeName=` | `metadata.name` |
| `device` | `Device=` | `volume.podman.io/device` |
| `type` | `Type=` | `volume.podman.io/type` |
| `mount_options` | `Options=` | `volume.podman.io/mount-options` |
| `copy` | `Copy=` | not mapped; use `volume.podman.io/import-source` |
| `container_options` | `.container Volume=<name>.volume:…:Z,U` | no PVC annotation; Podman applies the mount label |
| `reclaim` | unit lifetime/manual policy | not mapped; `kube down` keeps volumes unless `--force` |

Rules:

- Default `reclaim` to `retain` for a bind-backed external directory. A
  `delete` policy is only for scratch or `emptyDir`-like volumes.
- `type=bind` (not only `o=bind`/`Options=bind`) so Podman validates the
  device and Quadlet adds `RequiresMountsFor=`. The `Z`/`U` relabel and chown
  are container mount options, not volume-create mount options.
- If `assert_mount` is set, add `AssertPathIsMountPoint=` to the generated unit
  (or a typed assert in the allocator). It is a check, not a mount.
- Do not model capacity, access modes, StorageClass or provisioning. Podman
  ignores the PVC `spec`, and a single host has no scheduler.
- Do not auto-delete a volume whose data is outside Podman's storage. Removing
  the volume object is safe for the data, but a later automated recreate can
  still surprise; keep it a manual maintenance step.

## What to reuse

- **Quadlet** for the two local containers and their volumes: `.volume` with
  `Device=`/`Type=bind`, `.container` with `Image`, `ContainerName`,
  `Volume`, `Network=host`, `StopTimeout`, `RunInit`, `HealthCmd`,
  `HealthOnFailure`, `Environment`, `WorkingDir`, `Exec`, `AutoUpdate`.
- **Podman's idempotent verbs** for the build: `rmi --ignore`,
  `manifest create --amend`.
- **Podman kube play** only where systemd is absent: a PVC with
  `volume.podman.io/*` annotations, `hostPath` with `DirectoryOrCreate` or
  `Directory`, `emptyDir` for scratch, and `kube down` retention.
- **systemd `RequiresMountsFor=`** and `AssertPathIsMountPoint=` for the
  external disk, plus fstab/automount so the mount is a systemd unit.
- **tmpfiles.d** for host directories, symlinks, static file seeding and
  age-based cleanup where the distribution's `systemd-tmpfiles` already runs.
  On a non-systemd host, depend on `systemd-utils[tmpfiles]`, `seedfiles` or
  `opentmpfiles` rather than writing a parser.
- **mise's `skip_if`/`sources`/`outputs` semantics** if typed conditions are
  added: skip is success and no work; a broken probe is a failure; freshness is
  file-based and records nothing on failure.
- **Pulumi's OCI provider** only if the Oracle host lifecycle becomes a
  declarative infrastructure problem; it is not a maintenance-job engine.

## What to build

1. The step list, local first, with the semantics above.
2. The volume schema only if upkeep must render Quadlet and kube from one
   source. Otherwise let Quadlet own the volume and reference the unit.
3. A tiny tmpfiles subset only if a non-systemd host with a container runtime
   becomes a target. Restrict it to the line types actually used, implement
   precedence and `--dry-run`, and keep the file format identical.

## What not to build

- A tmpfiles engine with the full type/modifier/ACL/xattr/capability surface.
- A PVC provisioner, StorageClass controller, CSI driver or HA volume manager.
  The minimal prior art (local-path-provisioner) is mkdir/rm plus a helper pod;
  the real end (Mayastor) is a separate project.
- A container supervisor; Quadlet/systemd and process-compose already are.
- A reconciler or state database in the allocator. Upkeep is a DAG scheduler,
  not a controller.
- A general exec-predicate DSL. Typed checks plus idempotent verbs cover the
  current cases; one boolean `exec` check with systemd's exit ladder is the
  maximum if a real predicate appears.

## Recovery and shutdown, in one page

The detailed evidence is in [files and volumes](files-and-volumes.md).

- Containers: Quadlet's generated unit uses `podman run --replace --rm`,
  `ExecStop`/`ExecStopPost` with `podman rm -v -f -i`, and `KillMode=mixed`.
  A leftover container is replaced at start; a clean exit removes it; a dead
  conmon is cleaned by `ExecStopPost`; `StopTimeout` gives SIGTERM its grace
  period before SIGKILL. The old "stop and remove if it exists" guard is
  redundant.
- Volumes: `podman volume create --ignore` is idempotent, but options are
  immutable and a wrong volume must be removed and recreated explicitly.
  `type=bind` validates the device at create time; it does not revalidate on
  every start. `MountCount` resets after reboot; `volume rm` force-unmounts.
  This is recovery from missing state, not reconciliation of changed state.
- Shutdown: with a systemd-managed external mount, the start order is
  container → volume service → mount → device; at shutdown the container's
  `After=` on the mount makes it stop first, and Podman unmounts the bind when
  the last user stops. The volume service itself is a oneshot and is normally
  inactive. Add the `[Install]` target and, for rootless, linger. If udisks
  mounts the disk without a `.mount` unit, the container still stops
  gracefully, but the mount ordering is not enforced; unmounting or unplugging
  can race the container.
- `podman system check --quick --repair` is for image/container storage, not
  volume mounts. Use it as a rare maintenance job, not as the recovery story.

## Pitfalls

- `podman kube play` is apply-once: `--replace` restarts, PVC options are
  immutable, the PVC `spec` is ignored, and `Job` has no controller semantics.
- `o=bind` skips the device-existence check; `type=bind` does not.
- Quadlet `.volume` is a oneshot with `--ignore`; it does not reconcile changed
  options. A changed `Device=`/`Options=` needs an explicit remove/recreate.
- `podman auto-update` requires systemd units; it is digest-based and restarts
  the unit. It is not available to a bare `kube play` workflow.
- Quadlet requires cgroup v2. `Type=oneshot` has `TimeoutStartSec` disabled by
  default, and `RuntimeMaxSec` does not apply to it.
- `:Z` relabels and `:U` recursively chowns the bind source. Both are safe only
  if the directory is dedicated to the container.
- `tmpfiles.d` needs `/proc`; `f`/`w` write one short line; `C` only fills an
  empty destination; `!` lines are boot-only; `--root` bypasses NSS.
- A systemd `RequiresMountsFor=` edge only has effect when a mount unit exists.
  An udisks mount is not automatically a systemd mount unit.
- `ExecStop` is `podman rm -f`, not `podman stop`; it is graceful only if the
  application handles SIGTERM and `StopTimeout` is set. Test the stop path.

## Validation and migration order

1. Prove the Quadlet volume on a scratch directory: create a temporary `.volume`
   and `.container`, `systemctl --user daemon-reload`, start, inspect
   `podman volume inspect` (`Mountpoint`, `MountCount`, `Options`), stop, and
   confirm the container is removed and the volume unmounts. Then test the same
   with the external disk and a systemd-managed mount.
2. Inspect the generated unit with `systemctl --user cat` and run
   `systemd-analyze verify` on the extracted unit. Quadlet's own
   `podman quadlet print` shows the source, not the generated service.
3. Validate kube YAML with `podman kube play --validate strict`, using a scratch
   pod/volume name; `--start=false` creates without starting. A true dry run
   needs a scratch name and `kube down` afterwards.
4. Convert one script at a time, keeping the old script in the checkout as
   rollback material. Start with `syncthing`, then `transmission`, then
   `podman-build`.
5. Add steps to the allocator only after the local step runner is tested with
   the three-step build; do not add remote steps until there is a runner that
   keeps one SSH connection.
6. Run `node docs/spec-check.mjs` and `./lint.sh` after any documentation or
   manifest change.

## Open decisions

These are candidates for a future record. No DR numbers are assigned here.

- Steps: `argv: string[][]` versus a separate `steps` field; per-step
  `allow_failure` or none; local-only first or remote support in the same
  change.
- Volumes: let Quadlet own them, or add a manifest volume schema that renders
  both Quadlet and kube YAML; default `retain` always?
- tmpfiles: only consume the distribution's implementation, or add a subset for
  a named non-systemd target; which target is that?
- Conditions: add typed path/env/command/container checks, or only the
  idempotent-flag and Quadlet route for now; if typed checks are added, asserts
  before conditions?
- Recovery: is an explicit "remove and recreate the volume" maintenance job
  acceptable, or should a changed volume definition refuse to start and require
  a manual step?
