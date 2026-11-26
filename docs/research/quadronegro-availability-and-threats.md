---
id: research-quadronegro-availability-threats
type: architecture-design
status: draft
title: "quadronegro pool: member-loss availability and access threat scenarios"
parent: index
references: [index, research-quadronegro-audit, research-quadronegro-design, research-multi-uid-access, research-workload-isolation-egress, declarative-upkeep-poc, system, decision-log]
---

# quadronegro pool: member-loss availability and access threat scenarios

This note registers the failure and attack scenarios discussed for the quadronegro
pool: what a LUKS member that disappears (or hangs) does to the single Btrfs
filesystem, which part of the fail-fast chain systemd already provides and
which part needs a unit of its own, what "degraded" can and cannot mean on this
device mix, and how much local access a physical opponent needs at each rung of
the ladder. It is a register, not an installed change: no unit, example or
manifest was altered for it except where the corrections in the second section
say so. The workload-side isolation and egress questions are in
[workload isolation and egress](workload-isolation-and-egress.md); the shape
itself is in [the candidate design](quadronegro-at-home-design.md) and
[the audit](quadronegro-at-home-audit.md).

Evidence is the systemd source at `054ca239` (`src/cryptsetup/cryptsetup-generator.c`,
`src/core/{mount,unit,transaction}.c`, `rules.d/64-btrfs.rules.in`) and the
btrfs-progs profile tables; no claim here is a live-host claim, because the
audit host has no `systemctl`, `cryptsetup` or `btrfs`.

## Corrections this round adds to the record

1. **The profile is `raid1`, not `raid1c2`.** btrfs has no `raid1c2` profile:
   `mkfs.btrfs` accepts `raid0, raid1, raid1c3, raid1c4, raid5, raid6, raid10,
   dup, single`, and two copies is plain `raid1` (`raid1c3`/`raid1c4` add
   copies). A manifest or command that says `-d raid1c2` is rejected, so the
   prose "RAID1c2" elsewhere in the tree means "RAID1, two copies".
2. **Degraded operation through fstab is not merely unreliable, it is
   impossible.** `rules.d/64-btrfs.rules.in` runs the `btrfs ready` builtin and
   sets `ID_BTRFS_READY=0`, hence `SYSTEMD_READY=0`, on every device of an
   incomplete multi-device filesystem. The generated `.mount` depends on the
   mapper `.device` unit, which never becomes ready, so the mount job waits for
   the missing member and then fails at `x-systemd.device-timeout` (90 s by
   default) without running `mount` at all. `degraded,nofail` cannot help.
3. **The crypttab example's key file is not a key file.** The example points
   `systemd-cryptsetup@` at `/etc/credstore.encrypted/luks-<uuid>`, which is
   AES-GCM ciphertext produced by `systemd-creds`. `systemd-cryptsetup` does
   not decrypt credentials; it would feed the ciphertext as the passphrase.
   The fix is a TPM2-bound keyslot (no key file at boot) or a drop-in that
   loads the credential and overrides `ExecStart=`.
4. **The unlock unit can hang forever.** The generator writes
   `TimeoutSec=infinity` ("the binary handles timeouts on its own"). On a hung
   USB device `cryptsetup open` blocks, and that job has no deadline. Bound it
   with `TimeoutStartSec=` in a drop-in.
5. **Two defects in `config/upkeep/quadronegro.json` bit exactly in this
   scenario.** `quadronegro-lock-members` asserted that all three
   `/dev/mapper/luks-*` nodes exist, so when a member had vanished the job
   failed at the assert and the surviving mappings stayed open. It now asserts
   only `command_exists cryptsetup` and marks each close `allow_failure`, so
   the job's contract is "close whatever is open"; the residual gap is that
   `allow_failure` also swallows a genuinely busy mapping, because the POC has
   no post-step verification kind (a documented non-goal in
   [the declarative note](../declarative-upkeep.md)). `quadronegro-stop-writers`
   still assumes `systemctl --user`, which stops nothing when the workload
   units belong to the system manager or to another user's manager — and which
   manager owns them is exactly the question the isolation note leaves open.

## Two different member failures

The scenarios the owner described are not one failure but two, and they take
different paths:

| failure | udev event | what systemd sees | what btrfs does |
| --- | --- | --- | --- |
| USB drive unplugged or its enclosure resets out | `remove` on the device | the member's `.device` unit goes away | keeps the device "present" in its metadata, all I/O to it fails |
| USB or SMR stall (link hang, SMR garbage collection) | none, for minutes | nothing | I/O blocks, then errors; the device is still "present" |

A surprise removal is usually aborted into a read-only filesystem, because a
metadata write that cannot reach a mirror aborts the transaction; data writes
return `EIO` first. That is a safety property, not a shutdown: it happens at an
unpredictable point, after writes were already issued, and it leaves the
workloads staring at `EIO`.

## What the fail-fast chain already does

The stop chain the owner asked for is, for the removal case, the *default*
dependency graph. No custom unit is needed to propagate it:

1. `crypttab` generated instance: `systemd-cryptsetup@luks-<uuid>.service` gets
   `BindsTo=` and `After=` on `dev-disk-by\x2duuid-<uuid>.device` (the
   generator emits it for every `/dev/`-shaped source), so the service is
   **stopped** when the member disappears.
2. The mapper unit: the generator symlinks
   `dev-mapper-luks-<uuid>.device/requires/` to the service, so the mapper's
   `.device` unit is stopped with it.
3. The mount: an fstab-origin `.mount` gets `Requires=` and
   `StopPropagatedFrom=` on its backing device unit (`mount.c`,
   `mount_add_device_dependencies()`), so it is **stopped** when the mapper
   unit goes. (`x-systemd.device-bound=` would upgrade that to `BindsTo=`.)
4. The workloads: `RequiresMountsFor=` becomes `Requires=` + `After=` on the
   mount unit (`UNIT_MOUNT_REQUIRES`), and a stop job on a required unit
   propagates to its dependents (`UNIT_REQUIRED_BY` carries
   `UNIT_ATOM_PROPAGATE_STOP`, `src/core/transaction.c`).

The chain has three holes, and each one is what makes a unit necessary:

- **The close is a second pass.** `ExecStop=systemd-cryptsetup detach` is a
  plain `DM_DEV_REMOVE`, so it returns `EBUSY` while the filesystem is still
  mounted. The stop job's `ExecStop` fails, and nothing closes the mapping
  afterwards. After the unmount succeeds the close must be retried — that is a
  unit (or the allocator's `quadronegro-lock-members` job), not the graph.
- **A failed service does not stop its dependents.** `Requires=` propagates
  stop *jobs*; only `BindsTo=` propagates a **failure**. Upgrading the mount's
  edge to `BindsTo=` is what makes "cryptsetup gave up" and "the device was
  unplugged" behave the same.
- **The hang case has no event at all.** Nothing in the graph fires when the
  device stays enumerated but stops answering, which is the normal shape of a
  USB or SMR stall. That needs a health check, not a dependency.

A minimal system-level set, then: the fstab mount (strict, `noauto`, pulled in
by an enabled target), a drop-in adding `BindsTo=`/`After=`/`OnFailure=` plus a
`JobTimeoutSec=` bound on the job (and `TimeoutSec=` under `[Mount]` if the
mount command itself needs one — `TimeoutSec=` in `[Unit]` is not a key), a
fault unit ordered after the mount that stops the writers,
unmounts and re-closes, and a timer that polls `btrfs device stats` and a probe
read for the silent case. `x-systemd.onfailure=` on the fstab line does the
`OnFailure=` part in one option, but it is v262 and newer than the hosts this
tree targets, so a drop-in is the portable form.

Two policy choices deserve to be explicit rather than implicit:

- **degraded**: mounting the pool with one member missing is a *different*
  system, not a mode of this one. After a degraded mount, btrfs can allocate
  single-profile chunks (the constraint checks are chunk-level since 4.14), and
  a member that returns is stale — it must be `btrfs device scan`ed and then
  replaced or scrubbed, never trusted. On this device mix the cost is also
  paid in time: a `btrfs replace` of a USB SMR member is a multi-day operation
  during which the pool is degraded.
- **reboot instead of limp**: after a member loss, "stop writers, sync the
  good members, then reboot" ends in a state that is guaranteed locked and
  crash-consistent; a graceful stop can hang in D-state on the dead device.
  Because `crypttab` is `noauto`, a reboot cannot silently come back degraded.

## State targets, not a script chain

The owner's shape is better than a stop script: two mutually exclusive targets
express the two states, and the "unreachable" property falls out of the
dependency graph instead of out of a conditional.

- `quadronegro-pool.target` is the **mounted** state. It `Requires=` the three
  `systemd-cryptsetup@` units *and* `var-mnt-quadronegro.mount`, `After=` them. A
  target cannot carry an assert, but a failed `Requires=` member fails the
  target's start, so a missing member leaves the target inactive — the mounted
  state is unreachable rather than degraded.
- `quadronegro-parked.target` is the **closed** state, `Conflicts=` the pool target,
  and it is the one enabled at boot (`WantedBy=multi-user.target`). Boot always
  lands parked; mounting is a transition someone asks for.
- `quadronegro-park.service` is the close pass: `sync`, unmount, close each
  surviving mapping by name, verify with `cryptsetup status`, and exit non-zero
  if anything survived (no `RemainAfterExit=`, so every transition re-runs it;
  no `AllowIsolate=`). It carries `After=` on the mount but deliberately
  **not** `Requires=` (that would pull the mount and a TPM2 unseal in when the
  enabled parked target starts it at boot, and a missing member would then take
  the parked target down), and **no** `ConditionPathIsMountPoint=` ("the mount
  is already down" is the member-vanished case, where the survivors still have
  to be closed — the script is idempotent instead). It is mandatory, not
  stylistic: the generated `systemd-cryptsetup@` units are
  `IgnoreOnIsolate=true` and `DefaultDependencies=no`, so neither `isolate` nor
  stopping the pool target closes a mapping.

Four rules make that composition work, and each of them is easy to get wrong:

1. **`stop X.target` stops only `PartOf=X.target` members** (and units that
   `Require=` X). `WantedBy=` alone starts a workload with the target and
   leaves it running when the target stops, so workloads need both
   `WantedBy=quadronegro-pool.target` and `PartOf=quadronegro-pool.target`.
2. **Targets nest freely**: a target may `Wants=`/`Requires=`/`After=`/
   `Conflicts=` other targets; the graph is a DAG, not a tree. Mutual exclusion
   is `Conflicts=` plus `After=` **on both sides**, and the ordering must sit on
   the unit that does the work: `After=quadronegro-pool.target` belongs on
   `quadronegro-park.service`, not only on the parked target, or the close pass
   starts in parallel with the pool target's stop and umount/close hit `EBUSY`
   while the workloads are still flushing. The switch itself is
   `systemctl start <the other target>` — `Conflicts=` stops the current one;
   `isolate` is not used, because it stops every unit the new target does not
   pull in, which is far more than a pool state change should touch.
3. **`nofail` is then correct on the fstab line**, and for a precise reason:
   nothing pulls the mount in at boot, the pool target is the only consumer,
   and its `Requires=` is what gates the state. `nofail` keeps a failed mount
   non-fatal to boot; it can never produce a degraded mount.
4. **Shutdown-direction preflight must be permissive about absence.** An
   `assert` (or `Condition=`) that requires the pool to be mounted before the
   unmount step skips every descendant, which means "member vanished" — the
   one case where the survivors must still be closed — never reaches the close
   step. The allocator manifest has that bug in `quadronegro-unmount` and is fixed
   by asserting only on tools and marking the `sync -f`/`umount` steps
   `allow_failure`; in systemd terms, the same rule says the close unit must
   `After=` the mount and tolerate a missing mapping.

## Availability arithmetic

With three members and two copies:

- one loss is survivable, two are not (`raid1` needs `devs_min` 2);
- btrfs cannot pin a replica to a device, so for a three-device filesystem
  roughly one third of the chunks have *both* copies on the two USB drives —
  losing the USB pair loses data even while the SATA member is healthy;
- the two USB members are the same class of device behind the same transport,
  so their failures are correlated (hub, power, controller, enclosure
  firmware), which is the case the "one failure" budget does not cover;
- drive-managed SMR adds stalls that look like failures and makes scrub,
  balance and replace expensive.

The consequence is counter-intuitive and worth stating plainly: this pool is
**less available** than a single-disk Btrfs filesystem on the SATA member,
because the SATA-only pool has no dependency on a flaky transport at all. The
four candidate policies:

| policy | summary | verdict |
| --- | --- | --- |
| strict | all members required; no member, no pool | correct default, cheap, fail-closed |
| strict + fail-fast | strict, plus the `BindsTo`/fault/health units above | what "reliably shutdown instead of running degraded" actually means |
| degraded-tolerant | custom mount service, `mount -o degraded`, tolerates one loss | possible, but it buys one correlated failure and pays in resync, stale members and SMR time |
| USB out of the pool | pool on the SATA member alone; USB drives as `btrfs send`/receive targets, mounted only for the backup window | recommended: removes the transport from the write path and gives a rollback point RAID never gives |

The last one is a trade, not a free win: a single SATA failure becomes a
restore from backup rather than an outage. For a CMR system disk and two
drive-managed-SMR USB members, that is the right trade.

## What an attacker needs

Assets, in descending order of what losing them costs: the keys themselves
(Infisical secrets and any human passphrase), the host root filesystem, the
pool plaintext, and the pool's availability.

The acknowledged boundary in the repository README is unchanged: privileged
local access decrypts, and root on the host reaches the keys. Two additions to
that boundary are worth recording because they are *cheaper* than "root":

- With the pool mounted, root can read the volume key straight out of the
  device-mapper table (`dmsetup table --showkeys`), so an attacker who owns the
  host while the pool is open can add a keyslot and keep access after the
  incident.
- `systemd-creds encrypt` without a TPM2 key is only as strong as
  `/var/lib/systemd/credential.secret`, which lives on the host's own root
  filesystem. Encrypted credential files plus that host key on the same disk
  protect against a leaked credential file, not against a seized disk.

### Remote

LUKS is not the remote boundary; the host is. A remote attacker must first own
the host — through SSH, the two internet-adjacent containers (`Network=host`
gives their GUIs and RPC endpoints the host's addresses), or the image supply
chain — and then either uses the unlock path (Infisical token, credential
files) or waits for the next unlock. Two mitigations fall out of that rather
than out of the cipher: keep the pool locked whenever no workload needs it
(the isolated per-disk lifecycle is a security control), and bind each
service's management port to loopback or a private network.

### Partial physical

| access | what it yields | roughly how long | what stops it |
| --- | --- | --- | --- |
| a free USB port on a running host | HID/BadUSB injection, USB kernel surface, or a denial by pulling a member | seconds to minutes, no tools | `usbcore.authorized_default=0` plus a `usbguard` allowlist; firmware port lockout |
| powered off, firmware unlocks into external media | tamper `/boot` (initrd, UKI, kernel command line) and exfiltrate keys, the Infisical token or a keyslot on the next boot | a USB stick and a couple of minutes | UEFI password, external boot disabled, Secure Boot with owner keys, TPM2 PCR-sealed unlock so a changed boot chain refuses instead of leaking |
| powered off, case opened, disks removed | image the members and attack the keyslot offline | a screwdriver | infeasible against a random 256-bit key with memory-hard Argon2id — unless the host root disk is taken too, which carries `credential.secret` and the encrypted key files |
| one USB member stolen or swapped | offline attack (fails), or a replayed stale member that a degraded pool may read from | one drive | treat a returning device as untrusted; never auto-rejoin; `noauto` everywhere |
| DMA or cold boot while the pool is open | the key from RAM | Thunderbolt/PCIe hardware, or a reboot plus a RAM read | IOMMU on, Thunderbolt authorization, firmware password, and a short unlock window |
| sustained access (implant, interposer) | everything | days and tools | tamper evidence, intrusion switch, off-host logging; no cryptographic defence at reasonable cost |

The cheap wins, in order: TPM2-bound keyslots (the volume key becomes
non-extractable and a stolen disk becomes useless even with the whole host
filesystem), then firmware lockout plus Secure Boot plus a PCR policy (closes
the two-minute attack, which is the cheapest one that wins today), then a USB
authorization policy (closes the port-side attacks and also refuses a swapped
lookalike drive), then mount hygiene (`nodev,nosuid,noexec,noatime`) and
keyslot-count monitoring from the upkeep DAG.

What to skip: defending against a patient opponent with the machine in hand.
TPM sealing without measured boot still gives "power button equals plaintext";
dm-integrity would detect a replayed disk image but costs roughly double the
writes, which is the wrong price behind two SMR members; a remote attestation
service only verifies the boot state it is told about.

### The host root volume is not the pool's problem

The owner cannot enable at-rest encryption for the host root on this machine:
Bazzite DX is an OSTree image (`ostree-image-signed:docker://ghcr.io/ublue-os/bazzite-dx`),
root LUKS is an install-time Anaconda decision, and `systemd-cryptenroll` only
adds keyslots to an existing LUKS volume — there is no in-place conversion.
The `ostree-image-signed` remote verifies the *image* signature, which is not
Secure Boot and does not measure the boot chain.

That does not block the pool. The two moves that make the unencrypted root
nearly irrelevant to pool confidentiality:

1. a **TPM2-bound keyslot per member** with the recovery passphrase in a
   separate keyslot stored offline, so no key material sits on the host;
2. **TPM2-sealed credentials** (`systemd-creds encrypt --with-key=tpm2`) for
   what must remain a file, so the ciphertext is useless off-machine even on
   an unencrypted `/var`.

What each rung buys, against a TPM2 keyslot:

| attacker | TPM2 keyslot alone | plus Secure Boot + PCR 7 |
| --- | --- | --- |
| holds the disks only | stopped — needs *that* TPM | stopped |
| holds the box, boots their own media | can unseal when PCRs happen to match (with Secure Boot off, PCR 7 is a constant) | stopped — PCR 7 reflects the boot chain |
| tampers with `/boot`, waits for a boot | still steals host secrets (SSH keys, tokens) at the next login | unlock refuses, loudly |

So TPM2 keyslots are worth doing regardless of root encryption; Secure Boot
(owner key via MOK, e.g. the `ujust` Secure Boot enrolment recipe on ublue
images — verify what this image actually ships) is worth attempting but not a
blocker. Keep the recovery passphrase: firmware and db updates move PCR 7 and
will lock the token out. Host-secret confidentiality stays "reinstall with LUKS
someday", which the repository README already acknowledges.

## Open questions

- Is there a TPM2 on the pool host, and which PCRs survive the Bazzite
  bootloader updates (7 and 11 are the usual pair; 12 and 14 are stricter)?
- Is the case physically reachable by anyone but the owner, and does the
  board expose an intrusion header?
- Are the LUKS keys random values from Infisical or human passphrases? The
  whole offline analysis changes with the answer.
- Does any workload need the pool mounted continuously, or can it be a
  maintenance window?
- Replace or remove the two USB members from the pool, and on what schedule is
  a `btrfs send` backup to them acceptable?

## Non-goals

- No unit, drop-in, `usbguard` rule or TPM enrolment is installed by this note.
- No claim that any of this stops a kernel or firmware exploit.
- No claim that a degraded pool is safe because the profile survives one
  loss; the SMR and USB failure modes are correlated.
- No new decision record: the policies above are still candidates.
