---
id: declarative-upkeep-poc
type: architecture-design
status: draft
title: "Declarative upkeep proof of concept"
parent: index
references: [research-overview, research-guards, research-upkeep-mapping, research-quadronegro-audit, research-quadronegro-design, research-quadronegro-availability-threats, research-workload-isolation-egress, research-multi-uid-access, research-cross-host-systemd, research-termux-orchestration, decision-log, system, execution-map]
---

# Declarative upkeep proof of concept

This document describes the **proof of concept** built from the research notes
in [research/overview.md](research/overview.md). It adds `steps`, `assert`,
`credentials` and `phase` to the upkeep manifest and adds declarative
replacements for the quadronegro lifecycle and for the composite scripts in
`bin/upkeep-*`. The old scripts are deliberately untouched and remain rollback
material; nothing here is installed, enabled or selected by default.

The status is `draft`: no decision record chooses these shapes yet. The
purpose is to test the ergonomics of the schema against real manifests and to
prove the execution semantics locally before a migration touches the live host.

## What is new

| field | form | meaning |
| --- | --- | --- |
| `steps` | `[string[]]` or `[{argv: string[], allow_failure: bool}]` | serial commands in one job; stop at the first failure |
| `assert` | object or list of typed checks | preconditions that fail the job loudly; descendants are skipped and no retry is consumed |
| `credentials` | `{id: source-path}` | encrypted credentials loaded by the systemd backend; IDs, never values, reach the manifest and `plan` |
| `phase` | `boot`, `maintenance` or `shutdown` | a selection label; `--phase` filters a run, it is not a second scheduler |

`argv` remains the single-command form. A job may have exactly one of
`argv`, `steps` or `script`; `script` still embeds POSIX shell as before.
The existing `config/upkeep/jobs.json` is unchanged and still
plans and runs.

The new schema is implemented in `bin/upkeep-everything-2.py`; the typed
checks live in `bin/upkeep_asserts.py` and the step runner in
`bin/upkeep_steps.py`. The marker fallback (`bin/upkeep-run-one`) forwards
`--steps`, so the tmux-only backend keeps the same job semantics.

### Step semantics

- Steps run serially in one executor: one transient unit, one tmux pane, one
  marker runner or one console process. Tokens are held for the whole job; a
  failure does not release them in the middle of the list.
- One job-level `timeout` and one `retries`; a retry starts the list again
  from the first step. There is no mid-list retry.
- The job's exit status is the failing step's status.
- `allow_failure: true` is the explicit escape hatch. The preferred form is an
  idempotent verb (`podman rmi --ignore`, `podman manifest create --amend`,
  `systemctl start`), not a tolerated failure.
- Logs prefix `step N/M`; `plan` prints the numbered list before anything
  runs.
- Remote steps still use **one SSH connection per job**. The runner builds a
  quoted POSIX body from the validated argv arrays and pipes it through
  `ssh ... sh -c`; a manifest string is never parsed by a shell. This keeps
  the DR-051 one-connection property while allowing serial steps.

### Assert semantics

`assert` is systemd's `Assert=`, not its `Condition=`: a failed check is a
failed job, not a quiet skip. The kinds are deliberately small:

| kind | argument |
| --- | --- |
| `path_exists` | path |
| `path_is_dir` | path |
| `path_is_mount_point` | path |
| `command_exists` | executable name |
| `block_device_exists` | `/dev/disk/by-uuid/` name, or an absolute path |
| `credential_present` | credential ID declared by the same job |
| `env_present` | environment variable name |

Both spellings normalize to the same check:

    {"type": "path_is_mount_point", "path": "/var/mnt/quadronegro"}
    {"path_is_mount_point": "/var/mnt/quadronegro"}

Checks are evaluated when the job is about to start, before resource tokens are
acquired. That is intentionally earlier than systemd's "at job start" rule: a
failed precondition cannot leak a token. A failed assert prints
`ASSERT <job>: <check> failed`, marks the job failed, skips descendants and
does not retry.

There is no condition-skip form yet. The research argues that most remaining
guards are non-idempotent verbs that idempotent flags remove; if a real skip is
needed later, it should follow mise's `skip_if` rule: skip is success, a broken
probe is a failure.

### Credentials

A job declares IDs and source paths only:

    "credentials": {
      "luks-3ddf2a7e-ca8a-42a7-be96-27cbdf1ca49b": "${HOME}/.config/credstore.encrypted/luks-3ddf2a7e-ca8a-42a7-be96-27cbdf1ca49b"
    }

The allocator fails the job **before starting it** when:

- the backend is not systemd (console, tmux-only, marker runner), so a
  credential-needing job never runs with a key on the command line or in the
  environment;
- a declared source path is missing;
- a `credential_present` assert fails.

With the systemd backend, the allocator passes
`--credential ID SOURCE` to `bin/upkeep_systemd_exec.py`, which adds
`--property=LoadCredentialEncrypted=ID:SOURCE`. Steps refer to the file as
`${CREDENTIALS_DIRECTORY}/ID`; the allocator preserves that one deferred
token and the step runner expands it from the unit environment. This is the
only deferred expansion; it is not a general shell or `$VAR` language.

Create user credentials with `systemd-creds encrypt --user`; system units use
`systemd-creds encrypt` and `/etc/credstore.encrypted/`. The POC uses user
credentials because the allocator itself runs in the user manager: its
preflight must be able to see the source path. A system-manager variant would
move that check into the unit (or drop it and let `LoadCredentialEncrypted=`
fail). A live deployment must replace the interactive `infisical login
status` flow with a read-only machine identity and a refresh job; that
provisioning is **not** part of this proof of concept. The acknowledged
privileged-local-access boundary does not change.

## The quadronegro manifest

The component name is a decision, not a style: DR-054 reserves `unraid` for the
`X-at-home` meme and names the pool `quadronegro` — one word, because systemd
escapes `-` as `\x2d` in path-derived unit names. Everything below follows that
spelling, including `/var/mnt/quadronegro`.

`config/upkeep/quadronegro.json` models the storage as **one Btrfs filesystem with
three encrypted member devices**, not as four independent volumes. It follows
the correction in [the audit](research/quadronegro-at-home-audit.md): unlock every
member, mount the filesystem once, stop writers before touching the mount,
unmount first, then close each mapping.

| job | phase | what it replaces |
| --- | --- | --- |
| `quadronegro-unlock-members` | boot | the member-unlock loop in `10-unlock.sh` / `20-unlock-cryptsetup.sh`, with explicit `cryptsetup luksOpen` and no udisks daemon |
| `quadronegro-mount` | boot | the `findmnt` / `udisksctl mount` fallback; one `mount UUID=<fs>` plus a `findmnt` check |
| `quadronegro-start-writers` | boot | the container start in `-start-syncthing.sh` / `-start-transmission.sh`; Quadlet owns the units |
| `quadronegro-stop-writers` | shutdown | the broad `podman pod/container stop --all` sweep; only the declared units, then `sync` |
| `quadronegro-unmount` | shutdown | the repeated `udisksctl unmount` sweeps; `sync`, then one explicit `umount` |
| `quadronegro-lock-members` | shutdown | the repeated `udisksctl lock` sweeps; one `cryptsetup luksClose` per member, then `sync` |

The "fourth" UUID (`a95e1c63-...`) is the filesystem/mount UUID, not a member.
The `open-by-uuid/` symlink in git history and the older `open.sh` mount that UUID,
while `luks2-by-uuid/` lists the LUKS members. The tree also carries a
`545db2db-...` member that the current scripts do not unlock; the live
inventory must decide whether it is a live member or stale history, with
`cryptsetup isLuks`. The manifest therefore mounts with
`mount UUID=a95e1c63-...` — one mount for the one Btrfs filesystem — and
asserts that the filesystem device exists before it starts.

The mount point is the stable `/var/mnt/quadronegro`; the current scripts and the
udisks fallback use `/run/media/<user>/<uuid>`. Installing the fstab example
changes only the mount path, not the filesystem contents, so the Quadlet bind
sources under `/var/mnt/quadronegro` reach the same data as the old
`/run/media/<user>/<uuid>` paths.

`~/unraid-at-home/DECLARATIVE.md` carries the same mapping for that
repository, records the `open-by-uuid`/`luks2-by-uuid` evidence and leaves
every script in place as rollback material.

### Why `/var/mnt/quadronegro` and not `/run/media/quadronegro`

On Fedora atomic (Silverblue, Bazzite) the root is a read-only composefs
image: `/usr` is read-only, `/etc` and `/var` are writable and persistent,
and `/run` is a tmpfs. A system mount unit can create its mount point on
either path (systemd calls `mkdir_p_label` before mounting), so
`/run/media/quadronegro` is not broken. It is still the wrong home for persistent
shared data: every `/run` directory is recreated at boot, so ownership, mode,
SELinux label and export roots are boot-local; `/run/media` is the udisks
namespace; and `/var` is a real subvolume that survives updates. `/etc/fstab`
and `/etc/crypttab` are honored on atomic hosts, so the mount can be declared
without a `/usr` change; only packages such as `cryptsetup`, `nfs-utils` or
`acl` need `rpm-ostree install` (or a container).

The per-workload access model that follows from this (per-uid read-only and
read-write views, rootless Podman, NFS/SFTP and the `systemd-homed`
question) is analysed in [multi-uid data access](research/multi-uid-data-access.md).

The manifest is an allocator-owned alternative, not a replacement for
systemd's own lifecycle. For unattended boot, the system manager should own the
unlock and mount:

- `config/quadronegro/crypttab.example` — one `systemd-cryptsetup@` member per
  LUKS UUID with key field `none`, i.e. a LUKS2 token (TPM2) does the unlock
  and no key file sits on disk. The credential variant needs a
  `LoadCredentialEncrypted=` + `ExecStart=` drop-in, because
  `systemd-cryptsetup` does not decrypt `systemd-creds` ciphertext; the example
  carries that drop-in and the reason it is not simply a key-file path;
- `config/quadronegro/fstab.example` — one Btrfs mount with repeated
  `x-systemd.requires=` for every member, so a missing member prevents the
  mount instead of producing a degraded filesystem silently;
- `config/quadronegro/quadronegro-pool.target.example`, `quadronegro-parked.target.example`
  and `quadronegro-park.service.example` — the two mutually exclusive states and the
  close pass: the pool target `Requires=` the members and the mount, so a
  missing member makes the *mounted state* unreachable rather than degraded,
  while the parked target owns boot. The oneshot exists because the generated
  `systemd-cryptsetup@` units are `IgnoreOnIsolate=true`, so no amount of
  target composition closes the mappings by itself.

Both files are examples and are not installed. The manifest is useful where a
systemd mount unit does not exist, as the shutdown step chain, and as the
testable schema.

What a missing or hung member does to that shape — the default stop chain and
its three holes, the strict/degraded policy options with their verdicts, and
the physical-access ladder — is registered in
[availability and threat scenarios](research/quadronegro-availability-and-threats.md);
the per-workload uid, slice and network split is in
[workload isolation and egress](research/workload-isolation-and-egress.md).

## Quadlet replacements

The two container scripts are expressed as Quadlet units:

| file | replaces |
| --- | --- |
| `config/quadlet/syncthing-data.volume`, `syncthing.container` | `bin/-start-syncthing.sh` |
| `config/quadlet/transmission-data.volume`, `transmission.container` | `bin/-start-transmission.sh` |
| `config/quadlet/hister-data.volume`, `hister.container` | the `podman run … ghcr.io/asciimoo/nogon:latest` line (named volume becomes a bind-backed `.volume`) |

The volumes use `Type=bind` and `Device=` (not `Options=bind`), so Podman
validates the device and Quadlet can add `RequiresMountsFor=`. The containers
keep the old image, `Network=host`, `RunInit`, health command, stop timeout
and `:Z,U`/`:z,U` mount options. The reclaim policy is retain: no unit
deletes the bind source, and a changed device or option needs an explicit
remove/recreate, never startup reconciliation.

`config/upkeep/declarative-poc.json` starts the Quadlet units in
`syncthing-poc` and `transmission-poc`. The old scripts' "stop and remove,
then recreate the volume" guards are gone: Quadlet's generated unit uses
`podman run --replace --rm`, and `podman volume create --ignore` is
idempotent.

## The build and Oracle replacements

`config/upkeep/declarative-poc.json` also replaces the composite scripts that
are pure verb sequences:

| job | replaces | shape |
| --- | --- | --- |
| `podman-build-poc` | `bin/upkeep-local/podman-build.sh` | three steps: `rmi --ignore`, `manifest create --amend`, `image build` |
| `oracle-<host>-services-poc` | `bin/upkeep-remote/oracle-services.sh` | three `systemctl` steps |
| `oracle-<host>-reapply-poc` | the second `oracle-services.sh` call | the same three steps after `dnf` |
| `oracle-<host>-containers-poc` | `bin/upkeep-remote/oracle-containers.sh` | three start/linger steps |

The two genuine composites stay scripts on purpose:
`oracle-<host>-swap-poc` is a state comparison, and
`oracle-<host>-network-poc` is a `printf | tee` pipeline. The mapping
document already concluded that neither should be absorbed by a declarative
file format.

## Trying it

Read-only inspection:

    python3 bin/upkeep-everything-2.py plan --manifest config/upkeep/declarative-poc.json
    python3 bin/upkeep-everything-2.py plan --manifest config/upkeep/quadronegro.json
    python3 bin/upkeep-everything-2.py plan --phase shutdown --manifest config/upkeep/quadronegro.json

Execution uses the same allocator and backends:

    python3 bin/upkeep-everything-2.py run podman-build-poc --local --manifest config/upkeep/declarative-poc.json
    python3 bin/upkeep-everything-2.py run quadronegro-mount --local --manifest config/upkeep/quadronegro.json

The quadronegro jobs require live block devices, a mounted `/var/mnt/quadronegro`,
passwordless `sudo -n`, and (for the systemd backend) user credentials. With
`--local` they fail closed at the first missing assert or credential; that is
the intended dry-run substitute. There is no execution path that accepts
credentials without systemd.

The proof-of-concept harness is host-neutral and uses fake tools:

    tests/upkeep-poc/run.sh

`./lint.sh` now runs it after the documentation gate, so a shape that drifts
fails the repository gate instead of only a hand-run check. It covers: numbered
plan output, phase selection, serial step order, stop-on-first-failure,
descendant skip, `allow_failure`, loud asserts, fail-closed credentials,
deferred `${CREDENTIALS_DIRECTORY}`, the one-SSH remote step transport, the
shutdown ordering, backward compatibility with the existing `jobs.json`, and
the rejection cases: an unknown job or step field, `argv` plus `steps`, a
script plus `argv`, an invalid phase, credentials on a remote job, an unknown
assert kind, an unknown expansion, an unknown default, and a job with no
action. It does not cover live `cryptsetup`, real `systemd-run` credential
loading, Quadlet unit generation, or an Infisical machine identity.

## Viability assessment

The reference is gated now: `./lint.sh` runs the POC harness after the
documentation gate, and the harness rejects shape drift. It is host-neutral,
which is also its limit: it proves semantics, not the host. No claim below is a
live-host claim; the current working container has no `systemd`, `podman`,
`cryptsetup` or `infisical`.

| candidate | new shape | evidence | verdict |
| --- | --- | --- | --- |
| `bin/upkeep-local/podman-build.sh` | `podman-build-poc` steps | serial order and stop-on-failure tested; plan shows 3 steps | replace; the guards were non-idempotent verbs |
| `bin/-start-syncthing.sh` | `config/quadlet/syncthing.*` | Quadlet source at `19c75a78`: `Type=bind` validates the device and adds a mount edge | replace; needs one live Quadlet run |
| `bin/-start-transmission.sh` | `config/quadlet/transmission.*` | same | replace; needs one live Quadlet run |
| `bin/upkeep-remote/oracle-services.sh` | `oracle-*-services-poc` steps | remote steps run in one SSH connection | replace after one live SSH run |
| `bin/upkeep-remote/oracle-containers.sh` | `oracle-*-containers-poc` steps | same | replace after one live SSH run |
| `bin/upkeep-remote/oracle-network.sh` | stays a script | `printf \| sudo tee` pipeline | keep |
| `bin/upkeep-remote/oracle-swap.sh` | stays a script | genuine state comparison | keep |
| `bin/-upkeep-act-logs.sh` | stays a script | move + zstd + `xdg-user-dir` | keep |
| `bin/-ssh-upkeep.sh` | stays a script | jq/heredoc generator | keep |
| `bin/-upkeep-everything.sh` | `upkeep-everything-2.py` | the existing allocator | already replaced |
| quadronegro unlock and mount | `config/upkeep/quadronegro.json` boot jobs | plans cleanly; asserts and credential rules tested | host-blocked |
| quadronegro shutdown | `stop-writers` -> `unmount` -> `lock-members` | lifecycle test proves the order | host-blocked; systemd should own final authority |
| quadronegro secrets | `credentials` + `LoadCredentialEncrypted` | fail-closed and deferred path tested | host-blocked; no machine identity yet |

Two host filters bound the claim. The Termux note
[termux-orchestration](research/termux-orchestration.md) re-runs the hypotheses
on a non-systemd Android host: the DAG, serial steps, typed file/environment
asserts, declared token weights, run lock and one-SSH-per-job transport survive;
the systemd executor, `tmpfiles.d`, Podman/Quadlet volumes and the shutdown-order
chain do not. [The cross-host note](research/cross-host-systemd.md) confirms the
other boundary: there is no upstream distributed systemd control plane. Fleet
was the closest cluster-level systemd and is gone; Kubernetes and Nomad are the
replacements. The allocator therefore stays a single-owner DAG, and a future
cluster is a separate control plane, not a manifest field.

What remains not viable, and why:

- the allocator is not a shutdown authority. It can express the chain, but a
  user-manager oneshot is not pulled into shutdown without a system unit, and
  the mount is a system-level unit;
- the external disk is a system mount while the Quadlet units are user units
  in the POC, so the ordering edge crosses managers. Moving the containers and
  volumes to system Quadlet, or ordering the mount before `user@UID.service`,
  is still the open decision;
- the fourth LUKS candidate (`545db2db-...`) and the Infisical machine
  identity are inventory/secret questions, not schema questions;
- `allow_failure` is on probation: idempotent verbs may remove the remaining
  need for it;
- there is no condition-skip form and no generic volume schema; Quadlet owns
  volumes, and the mapping argues those are the right omissions.

The old scripts were not deleted. They remain the rollback material and the
comparison baseline for every row above.

## What is deliberately not done

- No run-level lock. Two allocator invocations still do not coordinate, and a
  daily run could overlap the shutdown chain (DR-049 notes the same gap).
- No condition-skip form (`skip_if` / `Condition=`); only loud asserts.
- No generic post-step verification kind. The mount job uses `findmnt` as its
  second step; `umount` and `luksClose` fail on their own, and a dedicated
  "now it is gone" check is a follow-up.
- No automatic installation of the crypttab/fstab/Quadlet examples and no
  `deploy.sh` change.
- No credential provisioning, no TPM/clevis, and no change to the documented
  threat model.
- No volume schema in the allocator: Quadlet owns volumes, as the mapping note
  recommends.
- No retrofitting of `config/upkeep/jobs.json`; the POC manifests are separate
  so the current daily DAG is untouched.

## Open decisions for a future record

The research questions still stand: whether `steps` or nested `argv` is the
long-term field; whether `allow_failure` survives or idempotent verbs remove
the need; whether asserts stay before conditions; whether remote steps keep the
one-SSH transport; whether credentials are user or system credentials; and
whether the quadronegro lifecycle moves to system units with the allocator keeping
only maintenance jobs. The proof of concept exists to make those choices
testable, not to pre-empt them.
