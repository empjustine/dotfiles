---
id: research-quadronegro-design
type: architecture-design
status: draft
title: 'Candidate declarative design for the quadronegro pool'
parent: index
references: [index, research-quadronegro-audit, research-overview, research-files-volumes, research-upkeep-mapping, research-quadronegro-availability-threats, research-workload-isolation-egress, decision-log]
---

# Candidate declarative design for the quadronegro pool

This note turns the [pool audit](quadronegro-at-home-audit.md) into a
candidate design: what a declarative replacement would own, what the allocator
would need, and how to migrate without risking the Btrfs filesystem. It is a
proposal, not an applied decision; no unit, manifest or script was changed for
it.

## Model and invariants

Treat the storage as **one Btrfs filesystem with N encrypted member devices**,
not as N independent volumes. The owner reports RAID1c2 and one final mounted
filesystem UUID. That changes the target shape:

- unlock every member mapping before mounting;
- mount the filesystem once, at one mount point;
- stop every writer before that mount is touched;
- unmount first, verify no users remain, then close each mapping;
- never delete a bind-backed volume or sweep unrelated devices;
- keep secret values out of the repository, the manifest, argv, environment
  and logs.

The early `exit 0` in the current unlock scripts is compatible with this
model and is not itself a defect. The design replaces the mechanism, not that
semantic shortcut.

## Layered ownership

| layer | owner | responsibility |
| --- | --- | --- |
| secret acquisition | systemd credentials plus Infisical machine identity | fetch/cache LUKS keys; expose as files under `$CREDENTIALS_DIRECTORY` or in a credential store; never print them |
| device unlock | system manager (`systemd-cryptsetup@.service` or dedicated oneshot units) | one unit per LUKS member; key file only root-readable; optional TPM binding via `systemd-cryptenroll` |
| filesystem mount | system manager (`.mount` generated from fstab, or an explicit mount unit) | one mount for the B filesystem; `Requires=`/`After=` on all N cryptsetup units |
| containers and volumes | Quadlet, rootful or rootless | idempotent volume creation, graceful stop, retain policy, health policy |
| periodic upkeep | `upkeep-everything-2.py` | maintenance jobs that require the mount; no unlock/lock responsibility |
| shutdown | systemd unit ordering plus a shutdown-only manifest | quiesce, stop, sync, unmount, close; fail loudly |

This follows the conclusion already in [files and volumes](files-and-volumes.md):
an udisks mount has no systemd unit, so `RequiresMountsFor=` cannot order
the container chain. Use fstab with `x-systemd.automount`, an explicit
`.mount` unit, or `systemd-mount` so the mount is systemd-known.

## Multi-device mount sketch

With placeholder names (the live UUID inventory is still an open question):

```/etc/crypttab
luks-MEMBER1  UUID=<luks-uuid-1>  /etc/credstore.encrypted/luks-MEMBER1  noauto
luks-MEMBER2  UUID=<luks-uuid-2>  /etc/credstore.encrypted/luks-MEMBER2  noauto
luks-MEMBER3  UUID=<luks-uuid-3>  /etc/credstore.encrypted/luks-MEMBER3  noauto
```

```/etc/fstab
UUID=<btrfs-fs-uuid>  /var/mnt/quadronegro  btrfs  noauto,x-systemd.requires=systemd-cryptsetup@luks-MEMBER1.service,x-systemd.requires=systemd-cryptsetup@luks-MEMBER2.service,x-systemd.requires=systemd-cryptsetup@luks-MEMBER3.service  0  0
```

Repository evidence points to `a95e1c63-...` as the filesystem/mount UUID
(the tracked `open-by-uuid/` marker and the older `open.sh` mount it) and to
`545db2db-...` as a possible fourth member that the current unlock scripts
omit. Both still need the live `cryptsetup isLuks` check.

The repeated `x-systemd.requires=` option is the important part: systemd's
fstab generator adds both `Requires=` and `After=` for each named
unit, so the single Btrfs mount cannot start with a missing member. The
systemd source at `054ca239` also puts `systemd-cryptsetup@.service` in
a slice destroyed very late in shutdown, which keeps mappings alive until the
filesystem has been unmounted.

Use `noauto` plus an explicit `quadronegro-pool.target` (with
`WantedBy=multi-user.target`, enabled, since nothing else pulls the mount in)
if the disks are optional; do not add `nofail` unless not mounting at all is an
accepted outcome. Avoid `x-systemd.device-timeout=0`: an absent disk should
fail visibly, not hang boot forever.

### Strict versus degraded

The sketch above is the **strict** policy: every member is a
`x-systemd.requires=`, so an absent USB drive means the Btrfs mount does not
start at all. That is a deliberate fail-closed choice, not a degraded-mount
setup. The live device mix (one fast SATA CMR member and two USB drive-managed
SMR members) makes the difference important:

- Btrfs RAID1 (two copies) keeps two copies of each chunk. With three members
  it tolerates one missing device; it does **not** tolerate two. If both USB
  drives are absent, only the SATA member remains and RAID1 cannot mount (it
  needs at least two devices).
- RAID1 does not guarantee that every chunk has a copy on the SATA member.
  The two copies may both land on the two USB drives. Losing both USB drives can
  therefore lose data even though the SATA drive is still present.
- A degraded mount is a Btrfs mount option, `-o degraded`, and it only helps
  for devices missing at mount time. A USB device that disappears after mount
  causes I/O errors; Btrfs may remount read-only or abort the transaction.

`fstab` **cannot** express a tolerant policy, and this is the correction the
availability register records: udev's btrfs rule marks every device of an
incomplete multi-device filesystem `ID_BTRFS_READY=0`, hence
`SYSTEMD_READY=0`, so the mapper `.device` units never become ready and the
`.mount` job waits for the missing member and then fails at
`x-systemd.device-timeout` without ever running `mount`. `degraded,nofail` and
`x-systemd.wants=` on the USB members are therefore dead options; the strict
line in `config/quadronegro/fstab.example` is the only shape fstab can express. A
tolerant mount needs a system-level service that:

1. requires the SATA `systemd-cryptsetup@` unit and *wants* the USB ones with a
   device timeout;
2. runs `btrfs device scan`;
3. counts the present members and refuses to mount with fewer than two;
4. runs `mount -o degraded UUID=<fs> /var/mnt/quadronegro` (or the normal mount when
   all members are present);
5. verifies with `findmnt` and `btrfs filesystem show`.

When a USB member returns, run `btrfs device scan` and then `btrfs scrub` to
repair the stale copies; a `btrfs balance` may be needed to restore full
distribution. A udev or path unit can trigger the rescan, but the scrub and
balance should stay explicit maintenance jobs, not automatic boot work.

The failure propagation (what systemd already stops and what needs a unit of
its own), the availability arithmetic of three members with two copies, and the
physical-access ladder are registered in [availability and threat
scenarios](quadronegro-availability-and-threats.md).

Drive-managed SMR behind USB is the weakest part of this design. Random writes
and Btrfs metadata trigger SMR garbage collection and long stalls; USB resets
add transport errors. RAID1c2 doubles the writes and does not remove the SMR
jitter. This is not a configuration Btrfs refuses, but it is not a configuration
to trust without a backup. If the two USB drives are treated as unreliable,
RAID1c2 across them is a one-failure design, and the failure that matters is the
second USB loss.

For rootless containers, add `Before=user@UID.service` to the mount unit so
the user manager (and its Quadlet containers) stops before the mount at
shutdown. For rootful Quadlet, put the containers and their `.volume` units
in the system manager and let their `After=` edges provide the reverse stop
order.

## Secrets

The current interactive `infisical login status` flow cannot be a
schedulable boot dependency. Candidate sequence:

1. Create an Infisical machine identity with read-only access to the single
   prod project; pin the CLI version and use
   `infisical secrets-manager secrets get --plain --silent` with
   `INFISICAL_TOKEN` from a credential, or the documented universal-auth
   login flags.
2. Store the long-lived client secret as an encrypted systemd credential
   (`systemd-creds encrypt` for system units, `--user` for user units).
3. A refresh job writes each LUKS key into a root-only credential store or
   passes it via `LoadCredentialEncrypted=` to the unlock unit. No key
   material is written into the repository, the manifest, argv or environment.
4. Reject empty secret output explicitly. The audit verified that the current
   jq filter exits 0 on empty input and on `[]`.
5. Make the console/tmux allocator backends fail closed for jobs that declare
   credentials; only the systemd backend can provide credential files safely.

Caching encrypted credentials on the host means boot unlock does not depend on
the network or Infisical being reachable. It does not remove the documented
threat boundary: privileged local access still reaches the keys. TPM sealing is
an optional hardening step, not a different trust model.

## Allocator changes

Extend, do not replace, the DR-051/DR-052/DR-053 contract. A second manifest,
for example `config/upkeep/quadronegro.json` selected with `--manifest`, keeps
privileged disk jobs out of the daily general manifest.

| field | proposed meaning |
| --- | --- |
| `assert` | typed checks: `path_exists`, `path_is_mount_point`, `block_device_exists`, `command_exists`, `credential_present`; failure is loud, not a retry |
| `credentials` | map of `{id: source}`; IDs only in the manifest; executor adds `-p LoadCredential=id:path` or `LoadCredentialEncrypted=` |
| `steps` | serial `string[][]` within one job: one token set, one timeout, one executor, stop at first failure |
| `phase` | optional `boot` / `maintenance` / `shutdown` label for selection and documentation; not a second scheduler |
| `retries` | keep 0 for shutdown jobs; a failed unmount must be reported |

Also needed: a run-level lock so a daily run cannot overlap a shutdown chain
(DR-049 already notes the gap), `plan` output that prints credential IDs
but never paths to secret values, and a per-step timeout policy that mirrors the
serial-oneshot semantics in [guards and steps](guards-and-steps.md).

The executor change is small: `upkeep_systemd_exec.py` already builds a
`systemd-run` argv; add credential properties there and pass
`$CREDENTIALS_DIRECTORY` to the job without putting secrets in
`Environment=`. Scripts must use an absolute path captured before
`sudo`, because sudo's environment reset removes that variable.

## Graceful shutdown chain

The systemd unit owns ordering and `TimeoutStopSec=`. The allocator can
express the step chain, but it cannot by itself be the final authority at
shutdown. Required order:

1. wait for application sync: Syncthing folder completion through its API with
   a deadline, and Transmission daemon/torrent quiescence. The current
   `cli show connections` check is not a completion check.
2. stop containers with their configured `StopTimeout=`; propagate a
   non-zero result as failure.
3. verify volume `MountCount` is zero and no process still uses the mount.
4. `sync` / `sync -f <mountpoint>` where available.
5. unmount the one Btrfs mount; verify with `findmnt`.
6. `cryptsetup luksClose` each explicit member mapping; no `find /dev`
   sweeps and no lazy unmount.

If sync is incomplete at the deadline, the policy must be explicit: either
extend the stop timeout up to a hard ceiling and report failure, or accept the
unmount with a visible warning. It must not be silently skipped. Locking before
unmount, parallel `xargs` and repeated cleanup sweeps from the current
script are removed.

The shutdown job chain can be expressed with `after` edges reversed for
stop order and a dedicated resource token, for example
`quadronegro_shutdown=1`, but it must be anchored in a systemd oneshot with
normal default dependencies so it is pulled into `shutdown.target` or the
user manager's `exit.target`.

## Containers and volumes

Convert the two container scripts to Quadlet units:

- `.volume` with `Type=bind` and the external directory as `Device=`;
  `Copy=false`; one volume per container data directory.
- `.container` with `ContainerName=`, `StopTimeout=`,
  `HealthOnFailure=restart`, `Network=host`, `RunInit=` and the
  `.volume` unit reference so `Requires=`/`After=` are added.
- Keep `:Z,U` on the **container** mount, not in the volume's
  `Options=`; test relabel/chown on a scratch directory before migrating.
- Reclaim policy stays `retain`. A changed device or option needs an
  explicit remove/recreate job, never an automatic startup reconciliation.
- Never run the current `podman volume inspect | jq | volume rm` cleanup.
  It deletes volumes whose `Options.device` is absent.

Rootless Quadlet needs linger to survive logout; rootful Quadlet lives under
`/etc/containers/systemd/` and uses root-owned storage. Both are viable;
the choice decides whether ordering is precise in one manager or coarse via
`user@UID.service`.

## Migration order and validation

1. Inventory the live host: LUKS member UUIDs, Btrfs filesystem UUID, mount
   point, Podman mode, Infisical CLI version, systemd version, TPM presence.
2. Prove one scratch bind volume and one scratch container with Quadlet, then
   inspect the generated unit with `systemctl cat` and
   `systemd-analyze verify`. Confirm stop removes the container and
   unmounts the volume.
3. Create the encrypted credentials and test that an empty/failed Infisical
   fetch fails the job, not an empty-key unlock.
4. Install the crypttab and mount units with all member dependencies. Test a
   missing-member case: the mount must not appear.
5. Move Syncthing first, then Transmission, keeping old scripts as rollback.
6. Add the quadronegro manifest and run `plan`; then run the maintenance chain
   with `--local` only where credentials are not required.
7. Exercise shutdown with checksums on a scratch file and a forced sync
   deadline; confirm container stop, unmount, `luksClose`, journal entries
   and exit status.
8. Try two concurrent allocator invocations to verify the run-level lock.

Run `node docs/spec-check.mjs` and `./lint.sh` after any documentation
or manifest change.

## Non-goals

- No new secret store, CSI driver, reconciler or kernel-bypass wrapper.
- No change to the acknowledged privileged-local-access threat model.
- No automatic volume deletion or changed-option reconciliation.
- No replacement of the allocator's DAG with a shell monolith; the quadronegro
  workflow is a manifest plus small scripts and systemd units.

## Status

Draft proposal. It depends on the live-host answers in the audit; until those
are recorded, UUIDs and unit names here are placeholders. A future decision
record should choose rootful versus rootless, the exact sync policy, and
whether the allocator gains credential/step fields or the quadronegro jobs stay
script-wrapped.
