---
id: research-unraid-audit
type: architecture-design
status: draft
title: 'Findings: unraid-at-home upkeep and declarative upkeep'
parent: index
references: [index, research-overview, research-files-volumes, research-upkeep-mapping, decision-log, system]
---

# Findings: unraid-at-home upkeep

This is a static audit of `~/unraid-at-home/` as it relates to
`bin/upkeep-everything-2.py` and the existing upkeep research. It records what
the scripts do now, which findings survive scrutiny, and which one was wrong.
Nothing here is a decision record or a migration plan; the companion design
note is [unraid-at-home design](unraid-at-home-design.md).

## Method and correction

The audit read the three current scripts, the unraid repository history, the
allocator and executors, the upkeep manifest and the dated records in
[DECISIONS.md](../../DECISIONS.md). It also checked systemd source at
`054ca239` (2026-11-21) and the local `jq` behaviour. The shell used for the
audit is a minimal container: no `systemctl`, `podman`, `cryptsetup`,
`udisksctl`, `infisical` or `tmux` is installed, so no claim here depends on
a live run of the target host.

One finding from the earlier review is corrected. The three UUIDs passed to
`10-unlock.sh` / `20-unlock-cryptsetup.sh` are not three independent volumes:
the owner reports one Btrfs filesystem using RAID1c2 across the member devices,
with the same final mounted volume UUID. On that model, the early `exit 0` as
soon as one mapping is mounted is intentional. The mount succeeds on one member
because the filesystem is shared; the script does not need to mount each mapper
separately. The real requirement is that **all member mappings exist before
that one mount**, and that one mount owns the filesystem. The "extra" UUID in
`90-unmount-lock.sh` is a filesystem/mount UUID rather than a fourth LUKS
member. The earlier tracked tree settles it: `open-by-uuid/a95e1c63-...` is
the mount marker used by `open.sh` (`udisksctl mount --block-device
/dev/disk/by-uuid/a95e1c63-...`), while `luks2-by-uuid/` lists the members.
That tree also carries `luks2-by-uuid/545db2db-...`, which the current
scripts do not unlock; it is either a live fourth member or stale history,
and the live host must decide with `cryptsetup isLuks`.

## What the scripts do now

| file | current behaviour |
| --- | --- |
| `~/unraid-at-home/10-unlock.sh` | Checks the three LUKS UUIDs exist, fetches each key from Infisical to a `mktemp` file, `sudo udisksctl unlock`, exits on the first `findmnt` hit, otherwise `udisksctl mount` and exits on the first success. Requires an interactive Infisical login session. |
| `~/unraid-at-home/20-unlock-cryptsetup.sh` | Same shape, but replaces the unlock verb with direct `cryptsetup luksOpen`. Mounting still goes through `udisksctl`, and it keeps the same early-exit behaviour. |
| `~/unraid-at-home/90-unmount-lock.sh` | Stops all pods and containers with a 120 s grace period, removes "local" volumes whose device looks missing, calls `sync`, then sweeps all `dm-*`, `sd*` and `nvme*` devices twice in parallel with `udisksctl unmount` / `lock`, then repeats for four explicit UUIDs. |

The README in that repository already documents the acknowledged security
boundary (privileged local access can retrieve the key), the udisks dependency
chain, and the UUID-list discrepancy. The older tracked tree held only symlinks
under `luks2-by-uuid/`, `open-by-uuid/` and `disks/`; no key material was
committed. The current scripts are untracked work in progress.

## Findings that still stand

### 1. Secret acquisition is not unattended-safe

Both unlock scripts gate on `infisical login status` (interactive user
session) and fetch the passphrase through a JSON pipe:

```sh
infisical secrets get ... "$uuid" | jq -j '.[0].secretValue' >"$keyfile"
```

Two failure modes were verified with the local `jq`:

- empty input and `[]` both make that filter exit **0** with no output, so a
  failed/empty fetch can produce an empty key file without failing the pipeline;
- `set -xe` traces the key-file path, and the key file lives in `mktemp`'s
  normal temporary directory; a killed subshell skips the cleanup trap.

The service-account path exists: the Infisical CLI checkout documents
`--method=universal-auth`, `INFISICAL_TOKEN`, and
`infisical secrets-manager secrets get --plain --silent`. A machine identity
plus a systemd credential is the declarative replacement; an interactive user
session is not a schedulable dependency. The installed CLI version must be
pinned because the scripts use the older `infisical secrets get` spelling.

### 2. udisks was a working hack, not a lifecycle contract

The README is correct about the dependency chain: `udisksctl unlock` goes
through D-Bus, udisksd, polkit and libblockdev before reaching cryptsetup. That
worked and still works where udisksd is available. It is not a systemd-known
mount, however. As [files and volumes](files-and-volumes.md) records,
`RequiresMountsFor=` only attaches to mount units in the same manager, so an
udisks mount gives no ordering edge for containers or shutdown. The direct
`cryptsetup luksOpen` variant removes the daemon dependency for unlocking but
still mounts through udisks, so it inherits the ordering problem.

### 3. Shutdown is not controlled

`90-unmount-lock.sh` has real problems independent of the Btrfs correction:

- `set -x` without `set -e`: stopped-container, unmount and lock failures do
  not change the exit status;
- lock is attempted before unmount on the first sweep, then repeated; parallel
  `xargs -P 2` can race the same mapper;
- broad `find /dev` sweeps can touch mappings and disks unrelated to this
  filesystem;
- the volume cleanup can delete unrelated Podman volumes. With
  `Options.device = null`, `jq --null-input -r '$volume_json.Options.device'`
  prints the string `null`, and `[ ! -e null ]` is normally true, so
  `podman volume rm` runs for a volume whose device was never set;
- `sync` happens after volume cleanup but without waiting for Syncthing or
  Transmission to stop writing. The existing health check
  `syncthing cli show connections` proves the CLI can connect, not that all
  folders are up to date.

A system reboot usually masks these races. A controlled shutdown must not rely
on that.

### 4. The allocator is not a lifecycle manager

In `bin/upkeep-everything-2.py`, `ALLOWED` fields are only `name`,
`hosts`, `host`, `resources`, `after`, `argv`, `script`, `timeout` and
`retries`. There are no steps, typed asserts, credential references,
lifecycle phase or stop actions. `env_variables()` knows only `DOTFILES`,
`HOME` and optional XDG paths. `bin/upkeep_systemd_exec.py` passes GUI/SSH
variables and sets `RuntimeMaxSec`; it does not load credentials or declare
shutdown ordering.

DR-049 explicitly records that concurrent allocator invocations do not
coordinate. A daily DAG and a shutdown chain therefore need a run-level lock or
a single owner. Also, the timer installed by `deploy.sh` only prunes tmux
windows and logs; `upkeep-everything-2.py` is invoked manually or by a future
timer.

### 5. Ordering cannot be fixed in the per-user manager alone

The systemd source at `054ca239` shows that a user manager receiving
`SIGTERM` starts `exit.target`, which pulls in `shutdown.target`; normal user
units with default dependencies are stopped. It also shows that all mount
units in a per-user manager are marked `extrinsic` by
`mount_is_extrinsic()`, so they are not automatically managed at boot or
shutdown. A user-level Quadlet container cannot order itself against a
system-level Btrfs mount. Either the whole lifecycle moves to system units, or
the system mount unit must be ordered before `user@UID.service` so the rootless
container manager stops first.

## What the prior art already answers

- [Files and volumes](files-and-volumes.md) and
  [upkeep mapping](upkeep-mapping.md) already conclude that udisks-mounted
  disks lack the systemd mount unit needed by `RequiresMountsFor=`, that
  Quadlet containers can stop gracefully with `StopTimeout=`, and that a
  bind-backed volume must default to `retain`.
- [Guards and steps](guards-and-steps.md) gives the semantics needed next:
  typed asserts fail loudly, conditions skip as success, and a serial step list
  stops on first failure with one job-level timeout.
- The systemd source at `054ca239` confirms that `LoadCredential=` and
  `LoadCredentialEncrypted=` are settable on transient units, that per-user
  encrypted credentials must be created with `systemd-creds encrypt --user`,
  that `systemd-cryptsetup@.service` lives in a slice destroyed very late in
  shutdown, and that fstab `x-systemd.requires=` may be repeated to require
  several units.
- DR-051, DR-052 and DR-053 define the allocator's current argv, host and
  backend contract. The unraid work should extend that contract, not replace
  it with shell strings.

## Open questions for the live host

1. Which UUIDs are LUKS member devices, and which is the Btrfs filesystem UUID
   or udisks mount label? The tracked `luks2-by-uuid/` and `open-by-uuid/`
   split answers the shape (`a95e1c63-...` mounts, the rest unlock), but the
   live host must still verify each candidate with `cryptsetup isLuks` and
   `findmnt`, including whether `545db2db-...` is a live fourth member.
2. Is the installed Podman rootless with linger, or rootful? Where are the
   container storage and the bind-backed volumes?
3. Is `/run/media/<user>/<uuid>` produced by udisks today, and is there any
   fstab entry or `.mount` unit already present?
4. Which Infisical CLI version is installed, and can a read-only machine
   identity be scoped to the one prod project?
5. What counts as "sync" for the shutdown gate: Btrfs writeback only, Syncthing
   folder completion, Transmission torrent completion, or all three?

## Status

Draft findings. The Btrfs correction is an owner-supplied fact; everything
else is reproducible from the repository and the referenced source. No files
under `bin/`, `config/` or `~/unraid-at-home/` were changed for this audit.
