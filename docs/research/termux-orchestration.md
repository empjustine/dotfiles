---
id: research-termux-orchestration
type: architecture-design
status: draft
title: "Dotfiles — Termux viability check for the orchestration research"
parent: index
references: [index, design, execution-map, decision-log, research-overview, research-guards, research-files-volumes, research-upkeep-mapping]
---

# Dotfiles — Termux viability check for the orchestration research

The four upkeep research notes were written against a full Linux host with
systemd, Podman/Quadlet and an external disk. This note re-checks their
hypotheses against the *actual* Termux/Android device, using measurements taken
on it rather than ARM64-Linux assumptions. It is a host filter over the existing
research, not a new design: nothing under `profile.d/`, `bin/`,
`config/` or the manifest was changed for it, and every verdict below says what
would have to be built, reused, changed or dropped. The upstream documents are
[the overview](overview.md), [guards and steps](guards-and-steps.md),
[files and volumes](files-and-volumes.md) and
[the upkeep mapping](upkeep-mapping.md); the current system is described in
[the systems reference](../system.md) and [the design](../design.md).

For the current declarative-services spike, **sections 1–12 are the filter that
matters**: they decide which manifest fields and executor assumptions survive
on a host without systemd, cgroups v2, user namespaces or mount tooling.
**sections 13–21 are Termux-only app-build, emulation, full-system-VM and shell-cost
research**; they are preserved for the Termux agent and are not adopted by the
desktop design. No desktop decision below depends on them.

## 1. Method and the host, measured

Read the four research notes and the records they cite (DR-049, DR-051,
DR-052, DR-053), then probe the live device on 2026-11-25 with POSIX tools,
Python 3.14 and the Termux service tree. Anything labelled *measured* below was
observed in that session; the probe commands are in §9. Two caveats: this is one
device, one boot, with the phone doing other work, so treat timings as ±20 %;
and "not in the package index" means the local `apt` index snapshot, not a
claim about the upstream world.

| fact | measured value | why it matters here |
| --- | --- | --- |
| platform | Linux 4.14.113, aarch64, Android 11 (SDK 30), SM-A505GT, no root, SELinux enforcing | no systemd, no cgroups v2, old kernel |
| CPU | 8 cores, 4× Cortex-A53 (`0xd03`) + 4× Cortex-A73 (`0xd09`), `schedutil`, 1.74 GHz current | little/big split; affinity is settable (`taskset` mask `ff`), per-core speed is not documented to us |
| priority | the app already runs at nice **-10** (Android top-app boost); `nice -n 12` lands at 2 | only *de-prioritisation* is meaningful; jobs cannot be boosted |
| memory | `MemTotal` 3.69 GB, `MemAvailable` 0.97–0.99 GB, swap 2.5 GB with ~1.27 GB free | a ~1 GB working budget is the real constraint |
| cgroups | **v1** (`schedtune`, `cpuset`, `cpuacct`, `memory`, `freezer`); `/sys/fs/cgroup` unreadable (EACCES); `memory:/` is the root cgroup; no `cpu.max`/`memory.max` | no per-job limits, no accounting, no `cpu.weight` |
| pressure | `/proc/pressure` **absent** (PSI is 4.20+) | systemd's pressure conditions have no input |
| `/proc` | readable: `meminfo`, `self/{stat,io,schedstat,status}`, `sys/kernel/random/boot_id`; **denied**: `stat`, `uptime`, `loadavg`, `vmstat`, `zoneinfo`, `net/dev`, `diskstats` | no load average, no CPU-time totals, no I/O stats (CPython here also lacks `os.getloadavg`) |
| process tree | `/proc/<pid>/task/<tid>/children` missing (kernel config); same-UID `/proc/<pid>/status` readable | tree walk = `/proc` scan; peer RSS/`VmHWM` is readable |
| init | no `systemctl`, `systemd-run`, `journalctl`, `loginctl` | the DR-052/DR-053 systemd backend does not exist |
| services | `runit` + `termux-services`: two `runsvdir` supervisors (both orphaned, pid 1), both shipped services (`sshd`, `ssh-agent`) **down**; a scratch service was auto-restarted 2 s after `SIGKILL` and stopped by `sv down` | supervision is real but not single-owner and not a job runner |
| boot hooks | Termux:Boot installed, `~/.termux/boot/` exists and is empty; Termux:API and Termux:Widget installed | a per-boot entry point exists (unused) |
| scheduling | `termux-job-scheduler` present (0 pending jobs); `--period-ms` floor 900000 (15 min), constraints `--network`, `--battery-not-low`, `--charging`, `--storage-not-low`, plus `--persisted` | the only native periodic/constraint engine |
| packages **absent** from the index | `podman`, `docker`, `systemd`, `systemd-tmpfiles`, `seedfiles`, `opentmpfiles`, `cryptsetup` | the volume/tmpfiles/systemd hypotheses have nothing to run on |
| packages present | `python` 3.14.10, `util-linux` (`flock`, `setsid`, `timeout`, `ionice`, `chrt`, `taskset`, `unshare`, `nsenter`), `coreutils`, `runit`, `termux-services`, `openssh` 10.6, `rsync`, `jq`, `zstd`, `node`, `shfmt`, `shellcheck`, `zsh`, `logcat`, `logger` | the scheduler and step runner are implementable |
| namespaces / fuse | `unshare -U` and `unshare -r` fail **EINVAL**; `/dev/fuse` **EACCES**; no `mount`/`umount`/`findmnt`/`lsblk` | rootless containers and mount orchestration are impossible, not merely uninstalled |
| storage | `/data` ext4 111 GB (49 GB free); `/storage/emulated/0` sdcardfs; SD card at `/storage/5DC6-4AE3`, FUSE, 922 GB (712 GB free), writable, `os.path.ismount` true | one slow "external disk", no mount lifecycle at all |
| disk speed | 4 MiB write: **12 ms** on `/data` vs **129 ms** on the SD card (~10×) | `extdisk` is a genuinely different resource class |
| mount table | `/proc/self/mounts` shows the SD card only under `/mnt/{installer,androidwritable,runtime}/…`, not at the path used | mount-table parsing is the wrong check; `stat`/`ismount` is right |
| death risk | `lmkd` running; **no** phantom-process monitor (that is Android 12+); Doze/App Standby and OEM battery managers still apply | jobs can vanish at any moment, with no shutdown hook |

## 2. Verdicts in one table

| # | upstream hypothesis | verdict on Termux | reason |
| --- | --- | --- | --- |
| H1 | typed conditions (`path_is_mount_point`, file/dir/executable, env, command) plus asserts that fail loudly, and skip-as-success | **viable, reduced set** | every type with a file/env input is cheap POSIX/Python; the *pressure*, *virtualisation*, *credential*, *security* and *container* families have no substrate (§3.2) |
| H2 | one boolean `ExecCondition` with 0/1–254/≥255 ladder | **viable, expensive** | one probe is a fork: 24–27 ms for `sh`, 72–110 ms for Python; keep at most one per job |
| H3 | `steps` as serial argv, stop at first failure, one job timeout, one token set, one executor, signals forwarded to the process group, no shell | **viable and verified** | a prototype ran steps, a whole-list timeout and a `SIGTERM` to the group; both children died, leader reported `-15` (§3.3) |
| H4 | a condition-skipped job joins `done`, releases tokens, consumes no retry, does not skip descendants | **viable** | pure scheduler accounting; no host dependency |
| H5 | weighted resource tokens, FIFO retry tickets, per-host tokens, run-level lock | **viable with one change** | weights must be *declared constants*, not measurements; the lock is `flock`, verified contended (§3.1) |
| H6 | `tmpfiles.d` as the directory/file layer, or a subset engine on a non-systemd host | **not viable, and not needed** | no implementation is packaged and none is installable here; the only line types the upkeep scripts need are `d`/`z`/`r`/`R`, which a five-line POSIX helper already does (§4.1) |
| H7 | Podman PVC-shaped volumes, Quadlet units, bind-backed volume on the external disk, `RequiresMountsFor=` ordering | **not viable** | no runtime, no user namespaces, no `/dev/fuse`, no mount tooling, and the SD card is a FUSE view with no mount unit (§4.2) |
| H8 | transient `systemd-run --user` units plus a `journalctl --user` follower pane | **not viable** | no systemd, no journald; a runit service is a restart supervisor, not a job with an exit code (§4.3) |
| H9 | controlled shutdown chain expressed as unit ordering (quiesce → stop → sync → unmount → close) | **not viable as ordering** | Android has no shutdown hook for apps; the process can be killed at any moment, so only *crash-consistent restart* and a manual quiesce command survive (§4.4) |
| H10 | remote jobs use one SSH connection per job, never one per step | **viable and more important here** | `ssh` 10.6 with `~/.ssh/config` hosts; a per-step connection would also multiply the 25 ms fork cost and the chance of a mid-run kill |
| H11 | container health probes (`HealthCmd`, readiness/liveness) as the readiness model | **not applicable** | no containers on this host; process liveness plus a typed condition is the whole surface |
| H12 | volumes are not reconciled — a changed definition needs an explicit remove/recreate | **not applicable** | no volume layer; the same principle survives as "never auto-repair state you did not create" |

## 3. What survives, and in what shape

### 3.1 The scheduler core survives unchanged

The DAG with weighted tokens, `after` edges, per-host fan-out, `plan`, structured
`argv`, timeouts and retries are host-independent Python; nothing in them needs
systemd, cgroups or containers. Measured building blocks:

- **Run-level lock:** `flock` is real util-linux. A second holder using
  `LOCK_EX|LOCK_NB` failed as expected in an 8-line probe (exit 7), so the
  DR-049 gap ("two concurrent allocator invocations do not coordinate") is
  closable with one file in `$XDG_RUNTIME_DIR` — with a `flock` timeout, because a
  stale holder must not block the next boot forever.
- **Token capacities must be declared, never measured.** With no PSI, no
  `cpu.max`, no `memory.max`, no `stat`/`loadavg`, there is no honest measurement to
  feed an adaptive claim. `disk` 1, `extdisk` 1, `net` 2, `cpu` 1, `mem` 1 as *constants*
  is the whole model; the interesting part is the split between `/data` and
  the SD card, which is a real 10× difference in write cost and therefore a
  real serialisation reason.
- **Retries need a restart story, not a fairness story.** DR-051's FIFO ticket
  scheme is fine, but on Android the more common "failure" is the *whole
  allocator* being frozen or killed by Doze, LMK or the OEM task cleaner. The
  manifest therefore needs a durable per-job record (attempt number, start
  time, status) so that a later run can resume or skip — otherwise "retries"
  only covers the case where the scheduler is still alive.
- **Accounting that does exist:** per-job peak RSS can be read from
  `/proc/<pid>/status` (`VmHWM`) while the child runs, or taken from
  `wait4`/`resource.getrusage(RUSAGE_CHILDREN)`; a probe measured 69 884 kB both
  ways for a 60 MiB allocation. That is enough to *calibrate* tokens by hand,
  not to drive them automatically. CPU time cannot be attributed (no
  `/proc/stat`, no `cpuacct` access), so concurrency must be bounded by count and
  deadline, not by CPU share.

### 3.2 Typed conditions: keep the file/env family, drop the rest

Cheap and verified on this host: `path_exists`, `path_is_dir`,
`path_is_mount_point` (`os.path.ismount` returns true for `/data`, `/proc`, `/dev` and
the SD card, false for `/storage/emulated/0` — so it is usable even though
`findmnt` is absent and the mount table lies), `path_readable`, `path_writable`,
`file_nonempty`, `dir_nonempty`, `file_executable`, `symlink`, `env_present`,
`command_exists` (deliberately *not* the DR-016 tool-discovery question, which
is about trusting a binary, not about whether a name resolves), and
`once_per_boot` keyed on `/proc/sys/kernel/random/boot_id` (readable, and already
the mechanism DR-038 uses for the WSL2 stamp).

Not implementable: memory/CPU/I/O **pressure** conditions (no PSI), the
virtualisation/capability/security/credential families (no substrate, no
`systemd-creds`), and the container family (no runtime). Host matching by
machine-id is awkward — Android's identifiers are not a stable machine-id — so
host selection belongs in the manifest's `hosts:` fan-out, exactly as the
research already concluded, plus `boot_id` for "per boot".

Cost discipline: a typed check is in-process (microseconds), an exec probe is a
fork (24–27 ms for `sh`, ~100 ms if someone writes it in Python). The upstream
advice "keep at most one exec predicate" is therefore not a style preference
here; it is 1.5–4 % of a generous 2 s job budget.

### 3.3 Steps: the upstream semantics are exactly right, and cheap to prove

A 30-line prototype verified the three properties the research asks for:

1. **Serial, stop at first failure** — `[exit 0] → [exit 3]` stopped at step 2
   with status 3 and never ran step 3.
2. **One timeout for the whole list** — a 1 s budget expired during step 2 and
   aborted the list (it does not restart the timeout per step).
3. **Process-group forwarding** — a child started with
   `start_new_session=True` that had two `sleep 30` children was killed with
   `os.killpg(pgid, SIGTERM)`; the leader exited `-15` and neither grandchild
   survived. This is the behaviour the research demands of the step runner and
   it is available without `systemd-run`.

What is *not* available is the systemd half of the model: no one-shot unit, no
`RuntimeMaxSec`, no per-unit journal, no `SuccessAction=`. A step list is a plain
background process whose exit status the allocator polls or waits for.

### 3.4 Android's own condition vocabulary is the one to reuse

`termux-job-scheduler` is a thin front end to Android's JobScheduler and exposes
typed, *system-evaluated* conditions: `--network any|unmetered|cellular|
not_roaming|none`, `--battery-not-low`, `--charging`, `--storage-not-low`,
`--period-ms` (floor 900 000 ms = 15 min) and `--persisted` (survives reboot).
That is the platform equivalent of `ConditionACPower`/`ConditionNeedsUpdate` and
it is *free* — the OS holds the job and applies the condition. Feed those flags
from the manifest instead of reimplementing them; keep them out of the
allocator's own condition set so that the two cannot disagree.

The catch, and it is the important one: JobScheduler has no exit-code contract,
no log stream and an execution window of its own. Treat it as the *trigger*,
never as the executor: the job script starts the allocator (with the run lock)
and exits immediately.

### 3.5 Observability without journald

`journalctl --user -u` and the journal-follow pane are gone. What exists:

- a run log directory (per-run, per-job files) is the primary record; it must be
  size-capped and rotated by the allocator itself, because nothing else will
  ("bounded ring" has to be built, not inherited);
- `termux-notification` / `termux-toast` for a human-visible failure signal —
  the closest analogue to "an assert is logged loudly";
- `logcat` is readable (verified), so a `logger`-style line is possible, but it
  is the system log and not a per-job buffer;
- `tmux` is installable from the index (not currently installed), so the pane
  backend is worth keeping as the "watch it happen" mode — the research's
  tmux-only state maps directly, and the console state maps to running the plan
  in the foreground.

The backend matrix should therefore shrink from four states to **two**:
supervised background (log files, notifications) and console (serial, inherited
stdout). That is not a loss of capability; it is the same degradation ladder the
research already describes, with the two systemd rungs removed.

## 4. What does not survive

### 4.1 `tmpfiles.d`: no processor, and no need

None of `systemd-tmpfiles`, `seedfiles` or `opentmpfiles` is installed or in the
index. Writing a subset parser would be building the thing the research
explicitly says not to build, for line types the upkeep scripts already express
as `mkdir -p`, `chmod` and an age-based delete. The format's real value on
this host is zero: its specifiers, precedence rules and modifier grammar solve
problems that a single-owner app sandbox does not have. The one prior-art idea
worth keeping is the *vocabulary* — "create the directory, set the mode, clean
by age" as declared actions rather than ad-hoc shell — and that is a 10-line
helper, not a format implementation.

### 4.2 Podman, Quadlet and the PVC model: blocked below the tooling

This is stronger than "not installed". `unshare -U` returns **EINVAL** (no user
namespaces for the app UID), `/dev/fuse` is **EACCES**, there is no
`mount`/`umount`/`findmnt`, no cgroup v2 write access, and `podman` is not in
the index. Every layer the research builds on is missing, so the bind-backed
volume on the external disk has no meaning: the SD card is a FUSE view whose
lifecycle belongs to Android, `os.path.ismount` is the only usable check, and
`RequiresMountsFor=` has nothing to order against even in principle. The
shutdown chain in [files and volumes](files-and-volumes.md) ("container →
volume → mount → device") cannot be expressed at all.

### 4.3 The systemd executor and the journal follower

No `systemctl`, `systemd-run`, `journalctl`, `loginctl`, no user bus. The
research's own fallback matrix already anticipated "without systemd, `--local`
and the marker runner remain"; on this host that is not a degraded mode but the
only mode. Two clarifications from the probe:

- **runit is not a substitute executor.** A scratch service was supervised
  correctly (auto-restarted ~2 s after `SIGKILL`, `sv down` stopped it), but a
  runit service is a *restart supervisor*: it has no exit code, no timeout, no
  bounded log and no one-shot semantics (`sv once` starts it but records
  nothing). Use runit for long-lived daemons (`sshd`, `ssh-agent`); do not map
  allocator jobs onto service directories.
- **The two `runsvdir` supervisors are a finding, not a bug to copy.** Both are
  orphaned with pid 1 and both watch the same directory; `runsv` holds the
  `supervise/lock`, so the duplicate is mostly inert, but it shows autostart is
  not single-owner. Anything that must run exactly once per boot needs its own
  `flock`, not a second supervisor.

### 4.4 Controlled shutdown: replace the chain with crash-consistency

There is no `shutdown.target`, no stop unit, no `Before=` edge, and no signal
that says "the device is going down". The process is killed by LMK, by Doze plus
an OEM battery manager, by the user swiping the app away, or by the kernel on
power-off. So the six-step shutdown chain becomes three different mechanisms:

1. **Crash-consistent restart** (the primary answer): every job must be safe to
   re-run or resumable from a durable marker; state files are written with
   `os.replace` (atomic rename) and, where a torn write would matter,
   `os.fsync` plus `sync`; no job may assume it will get a second phase. This is
   the audit's "a system reboot usually masks these races" problem, made
   explicit instead of hidden.
2. **Start-time asserts instead of stop-time ordering**: "the SD card is
   present", "no writer holds the run lock", "the previous run left no
   in-progress marker" are conditions evaluated *before* work starts, which is
   when they can still be acted on.
3. **An explicit, user-invoked quiesce command** for the cases where data
   integrity matters: stop the writers, `sync`, verify with a content probe,
   then report. It is not a shutdown hook; it is a manual step whose failure is
   visible. The research's "fail loudly, never silently skip" rule applies to it
   unchanged.

The part of the audit's finding 3 worth keeping is the *policy* list — wait for
writes to stop, `sync`, verify, never sweep unrelated devices. Block-device
sweeps, `luksClose` and `umount` have no equivalent here at all.

### 4.5 Measurement-driven capacity

Already covered in §3.1, but it deserves a separate "no": systemd conditions on
memory/CPU/IO pressure, `RuntimeMaxSec` accounting, `MemoryHigh=` and friends are
all unreachable. A scheduler that "reacts to pressure" on this host would be
guessing. Deadlines, declared weights and a concurrency cap are the honest
substitute, which is what the FIFO/DAG design already does.

## 5. Costs, measured

| operation | cost | note |
| --- | --- | --- |
| `sh -c 'exit 0'` | 24–27 ms | the price of one step or one exec probe |
| `python3 -c pass` | 72–110 ms | one Python-based probe/step is 3–4 shells |
| `sv status <name>` | 24–26 ms | text parse, no exit-code contract |
| `df -P /data` | 53–60 ms | avoid; `os.statvfs` in-process is ~0.1 ms |
| `os.statvfs` / `os.stat` | < 0.2 ms | use for free-space and device checks |
| `flock -n` acquire | ~1 ms | run-lock cost is negligible |
| 4 MiB write, `/data` | 12 ms | internal storage |
| 4 MiB write, SD card | 129 ms | ~10× slower; `extdisk` is a real token |
| interactive shell + full dotfiles chain | ~50–120 ms warm (per the execution map) | the budget the startup path already spends |

Consequences for shaping the implementation:

- **Keep the orchestrator off the shell startup path.** The existing
  `df_due`/`df_startup` guard is fork-free and is the right gate; a Python
  allocator is 72–110 ms *before* it does anything, so it belongs behind a
  once-per-boot or once-per-day stamp, or behind a Widget shortcut, never in
  `profile.d/`.
- **Budget steps in forks, not in lines.** A five-step job is ~125 ms of pure
  fork overhead plus the work; on a 2023 midrange phone that is fine for
  background upkeep and unacceptable for anything a prompt waits on.
- **Serialize the SD card, parallelize `/data` and network.** Two `net` jobs and
  one `extdisk` job is a sane default; two `extdisk` jobs at once will mostly queue
  on the FUSE layer anyway.
- **Size the log ring by the medium, not by habit.** 49 GB free on `/data` is not
  a licence to keep unbounded per-run logs; the allocator must cap and rotate.

## 6. Smallest useful manifest shape

This is the subset the verdicts above justify — the DR-051 `argv`/`hosts`
contract plus steps, the typed assert/condition pair, declared weights and a
per-boot marker. It is illustrative, not accepted:

    {
      "defaults": { "timeout": 900, "retries": 1 },
      "jobs": [
        {
          "name": "pkg-refresh",
          "resources": { "net": 1, "disk": 1 },
          "argv": [["pkg", "update", "-y"], ["pkg", "upgrade", "-y"]]
        },
        {
          "name": "sdcard-sync",
          "after": ["pkg-refresh"],
          "resources": { "extdisk": 1 },
          "assert": [{ "path_is_mount_point": "/storage/5DC6-4AE3" }],
          "condition": [{ "path_exists": "$HOME/dotfiles/bin" }],
          "argv": [["rsync", "-a", "$HOME/notes/", "/storage/5DC6-4AE3/backup/notes/"]]
        }
      ]
    }

Rules that go with it, taken from the research and adjusted here:

- `argv` is a list of `argv` lists; serial, stop at first failure, one timeout,
  one token set, one process group. No shell string, no `sh -c`.
- `assert` failures are loud and are not retried; `condition` failures are
  success, release tokens, consume no retry, and still satisfy dependents.
- Weights are declared integers; `extdisk` defaults to 1 because the medium
  serialises itself.
- A job that must survive the scheduler being killed writes its marker before
  starting and clears it after finishing; the next run treats a marker older
  than the timeout as crashed.
- `plan` prints numbered steps and the resolved token set; the run log prefixes
  `step N/M` and names the run id.

## 7. Build order on this host

1. **Reuse:** the DAG/token/`plan` core (port or import the existing
   `upkeep-everything-2.py` behaviour), `flock` for the run lock, `df_due` as
   the start-up gate, `termux-job-scheduler` as the trigger,
   `termux-notification` for failures, `ssh` with `ControlMaster` for remote
   jobs.
2. **Build, small:** the step runner (30 lines, semantics in §3.3); a durable
   per-job state file with crash detection; a log writer with rotation; the
   typed condition/assert family from §3.2; a quiesce command.
3. **Do not build:** a tmpfiles engine, a volume schema, Quadlet rendering, a
   journal follower, a pressure-driven scheduler, a container supervisor, a
   second service supervisor.
4. **Retire:** the four-state backend matrix (two states suffice), the
   credential fields (nothing provides `$CREDENTIALS_DIRECTORY`; a 0600 file
   under `$HOME` is the honest maximum), the shutdown manifest and `phase` label
   (there is no shutdown phase to select for).

## 8. Invariants worth adding to the design document

If any of this is adopted, these are the "do not break" lines for Termux:

- No job may depend on a shutdown notification; every job is safe to kill and
  re-run.
- No allocator code path runs on the interactive shell startup path; gating is
  `df_due`/per-boot stamps, and a Python start is never paid per shell.
- Token capacities are declared constants; no job's admission depends on a
  measurement the kernel does not expose here.
- Mount-point and device tests use `os.path.ismount`/`st_dev`/`statvfs`, never
  `/proc/self/mounts` text.
- Container, volume, tmpfiles and systemd-journal vocabulary never appears in a
  manifest field name, even as a placeholder — the field would be dead on the
  only host that reads it.
- `flock` is the only cross-process coordination primitive; `sv` supervises
  daemons, not jobs.

## 9. How these numbers were obtained

    # platform, kernel, CPU, memory
    uname -a; getprop ro.build.version.sdk; nproc; awk '/MemAvailable/' /proc/meminfo
    # what is blocked
    ls /proc/pressure; ls -la /sys/fs/cgroup; cat /proc/self/cgroup
    for f in stat uptime loadavg vmstat diskstats; do head -c1 /proc/$f; done
    # capabilities
    unshare -U --fork true; ls -l /dev/fuse; command -v podman systemd-tmpfiles tmux
    # services (scratch service, then remove it)
    mkdir -p "$PREFIX/var/service/dftest"
    printf '#!/bin/sh\nexec sleep 600\n' >"$PREFIX/var/service/dftest/run"
    chmod 700 "$PREFIX/var/service/dftest/run"; sv up dftest; sv status dftest
    kill "$(cat "$PREFIX/var/service/dftest/supervise/pid")"; sv status dftest
    sv down dftest; rm -rf "$PREFIX/var/service/dftest"
    # costs and semantics
    python3 - <<'PY'   # step runner / whole-list timeout / process-group SIGTERM
    ...
    PY
    # mount-point and storage
    python3 -c 'import os; print(os.path.ismount("/storage/5DC6-4AE3"))'
    df -h /data /storage/5DC6-4AE3
    # scheduling surface
    termux-job-scheduler --help; termux-job-scheduler -p

Not verified, and therefore not claimed: whether Termux:Boot actually fires on
this OEM build, whether Doze stops a given long job, what timeout
`termux-job-scheduler` imposes on a running script, and whether a wake lock
changes any of it. Those need a device experiment with the screen off, which is
the next thing to measure rather than assume.

## 10. Incidental documentation drift found

Two inconsistencies surfaced while following the citations; neither is caused by
this note:

- [the execution map](../execution-map.md) (layer diagram and the order list)
  and [the design](../design.md) (the invariant list) both describe a
  `lib/dotfiles.sh` that the entrypoint sources and every caller guards on, but
  the tree has no `lib/`: the helpers live inline in `src-dotfiles.sh`, which
  says so and cites DR-043 for the choice. The document contract still requires
  a header for `lib/` files.
- [the execution map](../execution-map.md) lists `config/upkeep/jobs.json`,
  `bin/upkeep-everything-2.py` and the `bin/upkeep*` executors in its tables and
  the research notes cite them throughout, but they are untracked working-tree
  files in this checkout, not committed history. Any "implement the Termux
  subset" work therefore starts by importing or committing the allocator, not
  by editing a tracked copy here.

## 11. Where this is actually used, and when SAF is required

The upstream work is desktop *service and persistence* maintenance: units,
volumes, tmpfiles, shutdown ordering. On this host the service half belongs to
runit and the persistence half belongs to three Android facts: the app's data is
wiped by a reinstall and is not in Android's backup, the SD card is the only
medium that survives that, and there is no schedule finer than 15 minutes. The
scenarios below follow from those facts, not from the desktop list.

### 11.1 The scenarios that have teeth here

| scenario | job shape | resources / conditions | why it is not just cron |
| --- | --- | --- | --- |
| **post-upgrade verification** | `pkg update` → `pkg upgrade` → verify → notify | `net`, `disk` | an upgrade is the commonest way a Termux setup breaks silently; the verify step must run *after* it, fail loudly, and must not retry into a loop |
| **home backup to the SD card** | `rsync -a` of dotfiles/notes/keys plus `pkg list-installed` | `extdisk`, assert `path_is_mount_point` | the card can be absent, and a partial copy into a missing mount is how backups get lost; the assert is the whole safety property |
| **library/media sync** (ZIM, music, photos) | `rsync`/`zstd` push to the card, resumable | `net`, `extdisk` (10× slower writes), trigger "charging + unmetered" | hours-long, kill-able, must resume rather than restart; the token pair is what keeps it from starving the rest |
| **cache and quota pruning** | age-based delete of `~/.cache`, npm/pip/go caches, apt lists, run logs | none | the vocabulary borrowed from `tmpfiles.d` (`d`/`z`/`r`/`R`) is exactly this; unbounded growth is a real failure on a phone |
| **periodic capture + rotation** | sample battery/thermal/network state, rotate the log ring | `termux-job-scheduler` at the 15 min floor | the capture is trivial; the *bounded ring* is the maintenance work, and nobody else does it |
| **service preconditions** | start/keep `sshd`, `ssh-agent`, `kiwix-serve` only when sensible | assert card/keys present, battery above a floor | runit supervises; the DAG only orders "card present → serve" and "keys present → sshd". Preconditions, not lifecycle |
| **cross-host upkeep** | pull dotfiles from the laptop, push to git, exchange files | `hosts:` fan-out, one SSH connection per job | the phone is one host among several; it must not need the desk machine up to run its own jobs |
| **reinstall recovery** | `upkeep plan` prints what is missing | asserts as an inventory diff | after a wipe this is the first command, and "what is absent" is more useful than "what failed" |

The driver behind all of it is unglamorous: Termux's app data is not covered by
Android's backup, a reinstall or "clear data" deletes `$HOME` entirely, and the
SD card is the only writable medium outside it. Put differently, the phone is
the *sole* copy of the notes, keys and dotfiles for as long as no job copies them
somewhere else.

### 11.2 The desktop-shaped jobs that do not come along

Restart-after-upgrade for units, volume lifecycle, Quadlet rendering, journal
vacuuming, unmount-before-shutdown, and "reconcile drift in declared state" all
assume an init system that can be ordered and a storage layer that can be
created. Here there is neither, so they are not adapted — they are deleted
(§4).

### 11.3 Storage access: direct paths, not SAF

The orchestration never touches the Storage Access Framework, and could not:
SAF yields `content://` URIs, while every primitive the design rests on —
`rsync`, `st_dev`, `os.statvfs`, `flock` on a file next to the data,
`os.path.ismount` — needs a path. What Termux actually has is **legacy external
storage**: `termux-setup-storage` grants the permission and the app keeps the
pre-scoped-storage behaviour, so shared storage and the card appear as ordinary
directories. Verified on this device:

| input source | how Termux sees it | automatable |
| --- | --- | --- |
| `$HOME` (app-private) | plain paths, fastest, backed up by nothing | yes |
| `/sdcard`, `/storage/5DC6-4AE3` (card root) | plain paths; write verified, `statvfs` and `ismount` work | yes |
| `/sdcard/Android/media/<pkg>` | readable path (listing succeeded) | yes |
| `/sdcard/Android/data/<pkg>` | **EACCES** even for the shell (listing denied) | no — the producing app must share/export, or write under `Android/media` |
| a cloud provider tree (Drive, Nextcloud) | only a `content://` URI through the document picker | no — a human tap, then a copy into a staged directory |
| `DCIM` / gallery visibility | direct write works, but MediaStore is not updated | needs `termux-media-scan` afterwards |

So the answer to "does it need SAF helper apps" is: **not for persistence, only
for crossing another app's boundary**, and in exactly two shapes — documents in
(`termux-storage-get` opens the picker and copies the chosen document into a
directory you name) and results out to a user-chosen destination
(`termux-share`). Both are interactive by construction, so neither can be a
DAG node. The design consequence is one convention instead of one field: a
`staged/` directory per consumed input, with `dir_nonempty` as the condition, so a
job whose input has not been picked yet skips as success (§3.2) instead of
failing. A manifest must **not** grow a `uri:` field; it would be dead on every
path this host can take.

Two caveats worth recording:

- **The whole store rests on legacy storage.** If the Termux app raised
  `targetSdk` to 30+ (where `requestLegacyExternalStorage` is ignored) and did
  not switch to a managed-access strategy, direct card access disappears, and
  with it the `extdisk` resource and the backup scenario — SAF would then be
  the only route, and it is not scriptable. A cheap guard is an assert on the
  storage class (`path_is_mount_point` plus a write probe) so the failure is
  reported instead of silently shrinking the plan.
- **Helper-app inventory is narrower than it looks.** `termux-wake-lock` ships
  in `termux-tools` and needs no companion app; `termux-storage-get`,
  `termux-share` and `termux-media-scan` are `termux-api` binaries and only work
  with the Termux:API app installed (it is, here). So the "SAF helper" dependency
  is real but confined to picker/share/media-scan/notification, never to reading
  or writing the card.

## 12. Isolation and privilege: Shizuku, a VM, and a second app

This section answers whether the gaps in §3.1, §4.5 and §11.3 can be bought back
without root — with ADB-graded access (Shizuku), with an emulated guest, or with
more apps. The short answer is that they can be bought back *partially and only
at the edges*: none of the three restores namespaces, cgroups or a fine-grained
jail, and two of them trade away safety rather than add it.

### 12.1 The privilege ladder, as measured

| what | measured | consequence |
| --- | --- | --- |
| capabilities | `CapEff: 0000000000000000` | **no capabilities at all** — no `mount`, no `chroot`, no `setuid` |
| seccomp | `Seccomp: 2` (zygote filter) | a job can only *add* a stricter filter, never remove one |
| user namespaces | `unshare -U` → **EINVAL**, `unshare -m`/`-p` → **EPERM** | no `bwrap`, no `nsjail`, no unprivileged mount/pid namespace |
| cgroup v1 control | `/dev/cpuset` and `/dev/stune` are `system:system 555`, `/sys/fs/cgroup` is `root:root 555` | cpu/memory cgroup tuning is closed to apps **and** to the shell uid |
| KVM | `/dev/kvm` absent | any VM is TCG (interpreted) only |
| app-private data | `/data/data` → EACCES | other apps' private state is unreachable by any of the three options |
| external data | `/sdcard/Android/media` readable, `/sdcard/Android/data` EACCES | as in §11.3 |
| `cmd` surface | `cmd deviceidle whitelist` answered, `cmd activity get-current-user` and `cmd appops get` threw SecurityException, and one probe **hung** without a deadline | a leak, not a door — and every `cmd` call needs a `timeout` wrapper |

### 12.2 Shizuku: shell is not root, and it widens the perimeter

Shizuku (installed here as `moe.shizuku.privileged.api`, currently idle — no
`app_process` server running) starts a **uid 2000** service under the `shell`
identity over ADB, and an authorized app can ask that service to run
shell-level operations; the app itself gains nothing it did not declare.
Self-pairing is possible on this device (Android 11 has `adb pair`, and
`android-tools` 37.0.0 is packaged), but the session dies on every reboot and the
pairing port and code change each time.

What it would actually buy, and what it would not:

- **Buys (real):** the denied `/proc` files — `stat`, `uptime`, `vmstat`,
  `diskstats` — so load and I/O *could* be sampled again, though per-job CPU
  attribution still would not exist; `cmd deviceidle whitelist +com.termux` and
  `am set-standby-bucket com.termux active`, which is the Doze risk from §1
  made manageable; `appops set com.termux MANAGE_EXTERNAL_STORAGE allow`, which
  is the §11.3 legacy-storage regression made recoverable; `cmd jobscheduler run`
  to trigger our own scheduled job early; and *reads* of other apps'
  `/sdcard/Android/data` — performed inside the shell process and streamed back,
  so a copy rather than a path, and still not a manifest field.
- **Does not buy:** namespaces (the shell uid has no `CAP_SYS_ADMIN` either), any
  cgroup write (555 plus SELinux), mounts, an SELinux domain change, or other
  apps' private `/data/data`.
- **Costs:** the trust boundary moves outward. Today a compromise of Termux is a
  compromise of one app's sandbox; with Shizuku it is a compromise of shell-level
  capability — appops, installs, logcat, other apps' external data. For a
  question about *isolation* that is the wrong direction, so it must be an
  opt-in for specific jobs, gated by a condition (a `rish` probe call), never on
  the critical path, and never silent.

Note the honesty boundary: the "buys" list follows from the Android permission
model, not from a live session on this device — Shizuku was installed but not
started during this probe. Everything in §12.1 is measured.

### 12.3 A TCG VM: containment of intent, not a security boundary

`qemu-system-aarch64` (11.1.3) and `qemu-utils` are packaged, so an Alpine
or Debian aarch64 guest is buildable. Without `/dev/kvm` it runs under TCG, and
on this SoC that means roughly 3–10× slower CPU, a 1–3 minute boot, guest RAM
carved out of the same ~1 GB the app has, and sustained load that a midrange
phone answers with thermal throttling. A 12 ms upkeep job inside such a guest
takes minutes; the VM is therefore *never* an executor for the DAG.

Its boundary is better than proot's and worse than it looks: the guest sees only
its virtual disk and a SLIRP network, so a careless command cannot delete the
host's files — genuine protection against **intent**. But the enforcing entity is
the QEMU userspace process, running with the app's UID, no capabilities, no
namespaces and the same seccomp level; the device model is a large C surface with
a long CVE history. A guest that *tries* to escape is attacking QEMU, from inside
the same sandbox as everything else. So: right for "run an untrusted toolchain or
an unknown binary with no shared folder", wrong to describe as a jail, and
useless against an attacker already inside Termux.

### 12.4 Several apps (or a second user): the only kernel-enforced boundary

Per-app UID separation plus a per-app SELinux domain, a private data directory and
a declared permission set is exactly the mechanism §12.1 shows is unavailable
inside one UID. Three ways to get more of it, in increasing strength:

- a **second terminal app** (a separate package, typically proot-based) — new UID,
  new `$HOME`, new prefix;
- a **self-built, renamed Termux APK** — you sign it yourself, no root involved,
  and get an independent sandbox with the same tooling;
- a **work profile or a second user** — a genuinely separate app sandbox that
  exists as a distinct identity, at the cost of profile-admin setup and switching.

The price is the same in all three: the shared `$HOME`, the shared `$PREFIX` and
therefore the whole dotfiles premise; several gigabytes of duplicated toolchain (the cost belongs to second
*terminals*; a purpose-built single-workload app is a few megabytes, §13);
and no `rsync` from one to the other except through shared storage, which is a
canal everyone can read anyway. It is the correct answer if the threat is "an
untrusted workload needs a different identity"; it is the wrong answer for "my
own jobs should not interfere", because the jobs are trusted code and what they
need is resource isolation, not identity isolation.

### 12.5 What actually substitutes for cgroups here

All measured, all unprivileged, all inherited across `fork`/`exec`:

- **`RLIMIT_AS` is enforced** — a 64 MB limit produced a `MemoryError` on a
  200 MB allocation, and `prlimit` can apply it to a child. That is the `mem`
  token made real: coarse (allocation failure rather than graceful throttling)
  but honest. `RLIMIT_FSIZE` caps a runaway write, `RLIMIT_CORE` is already 0,
  `RLIMIT_NOFILE` is 32768.
- **`chrt --idle 0` and `chrt --batch 0` work** — `SCHED_IDLE` is the closest
  thing to `cpu.weight` available here: upkeep never competes with the UI.
- **`taskset -c 0-3` works** — pin upkeep to the little cores and leave the big
  ones to whatever the user is doing.
- **`ionice -c 3` works** — idle I/O class, which matters precisely because the
  SD card is a FUSE view with no per-device throttling we can configure.
- **`setsid` + `killpg` (§3.3)** — the lifecycle half.
- **`PR_SET_NO_NEW_PRIVS` then a hand-written seccomp BPF filter** — the only
  syscall confinement available, since there is no `libseccomp` package and the
  zygote filter cannot be relaxed. Worth it only for a job running foreign code.
- **`proot` / `proot-distro` are not in this list** — ptrace path
  translation with no credential change is compatibility, not containment.

### 12.6 Verdict, and what it changes in the design

| option | restores | is it a security boundary? | verdict |
| --- | --- | --- | --- |
| Shizuku (shell uid) | `/proc` stats, appops/deviceidle/standby grants, other apps' external data as a copy | no — it *widens* the perimeter | adopt narrowly and optionally: measurement, the storage-class guard, the Doze whitelist, early job trigger; condition-gated, never on the critical path |
| TCG QEMU guest | a foreign distro, and a filesystem/network boundary around *intent* | weak — QEMU's own bugs, same UID | only for untrusted toolchains; never a job executor |
| second app / work profile / second user | a real UID+SELinux boundary, the platform's own | **yes** | only if the workload is untrusted; costs the shared `$HOME` and gigabytes |

Design consequence: an `isolation` field with three honest values — `shared`
(default), `hardened` (rlimits, `SCHED_IDLE`, affinity, idle I/O,
`no_new_privs`, optionally a seccomp filter), and `foreign` (a VM or a second app,
human-staged and condition-gated, never in the critical path). No value named
`sandbox` or `jail`: on this host those words would be false. And the framing
worth writing down is that Android has already provided the only real boundary —
the app sandbox — and every job in the DAG lives *inside* it; what is left to
engineer is exhaustion and accident, not adversary containment.

## 13. Building single-workload apps on the device

Whether the `foreign` level from §12.6 can be produced on the phone itself, with
no PC and no root: yes, with one missing input and one honest cost. The measured
state of the toolchain is better than expected, because a JDK is already here.

### 13.1 The toolchain, measured

| tool | state |
| --- | --- |
| `java`, `javac`, `keytool` | **installed** — OpenJDK 21.0.13.1, with 25.0.5.1 beside it |
| `aapt2` | absent from disk, **in the index** (964 KB) |
| `d8` | absent, **in the index** (14.7 MB); depends on `openjdk-21`, already installed |
| `apksigner` | absent, **in the index** (1.1 MB); same dependency |
| `zipalign`, any `android-sdk*`/`build-tools`, `gradle`, `kotlinc` | **not in the index at all** |
| `termux-open`, `am`, `pm`, `cmd` | present |

So the missing download is roughly 17–20 MB including aapt2's C dependencies — not
another JVM. Costs measured on this device: JVM start **0.24 s**; a trivial
`javac --release 8` **2.16 s**; a 2048-bit `keytool` keystore **2.33 s**
(2.5 KB, mode 0600). Consequence: this is a five-command shell script, not a
Gradle project, and Java only. `--release 8` still works on this JDK (with
obsolete-option warnings), which matters because the Android-28-era API is a Java
8 subset.

### 13.2 The one missing input: android.jar

Measured: `/system/framework` is world-readable, but `framework.jar` is **dex
only** (34 entries, 5 `classes*.dex`, **0** `.class` files), and no
`android*.jar` exists anywhere under `$PREFIX`. A compiler needs signatures, so:

1. **hand-written stubs** for the handful of APIs used, compiled once and passed
   only as `-classpath` (only `src/` becomes dex). A broadcast receiver plus a
   foreground service is about ten classes;
2. **one `android.jar`** (~20 MB) fetched once from a mirror — bandwidth, no
   maintenance;
3. build off-device, which is exactly what the question wants to avoid.

Option 1 has a second value: the stub directory is an exact statement of the API
surface the app depends on, which is what you want for something that must survive
a platform bump.

### 13.3 The build, start to finish

    keytool -genkeypair -keystore ks.jks -alias a -keyalg RSA -keysize 2048 \
        -validity 10000 -dname CN=upkeep
    javac --release 8 -classpath stubs.jar -d out src/*.java
    aapt2 link -o unsigned.apk -I stubs.jar --manifest AndroidManifest.xml
    d8 --min-api 28 --lib stubs.jar --output dex out
    apksigner sign --ks ks.jks --out app.apk unsigned.apk

Estimated 6–12 s per build, of which 2.2 s is measured (`javac`) and ~0.5 s is JVM
startup; `d8` and `apksigner` are unmeasured here. N apps are N builds from one
template with a different package name and action, plus one install each.
`zipalign` is not packaged: `aapt2` output is usually installable, and if the
installer objects, the 4-byte alignment of `resources.arsc` has to be done by hand —
a small, well-understood wrinkle rather than a blocker.

### 13.4 Two platform rules that decide the shape

- **`exec` is a targetSdk decision.** Apps targeting 29+ may not `execve` files in
  their own data directory. That is why Termux pins itself low, evidenced here by
  every binary under `$PREFIX` running. So a workload app that bundles a static
  aarch64 binary (Go with `CGO_ENABLED=0`) must target 28 — which installs fine on
  Android 11 and will not forever (newer Androids refuse very low targets; Play
  wants 34+, though sideloading is what this is).
- **Android supplies the supervisor §4.3 says Termux cannot have.** A `Service`
  plus `JobScheduler` plus a `BOOT_COMPLETED` receiver buys OS-level restart,
  constraint-aware scheduling, a per-app battery exemption and crash isolation.
  That is the real payoff, and it reframes the architecture: Termux becomes the
  *planner* (`plan`), and `foreign` jobs are executed by apps that Android
  supervises.

### 13.5 Installing without root

- `termux-open app.apk` (present) hands the APK to PackageInstaller through
  Termux's FileProvider: one tap per app, after a one-time "install unknown apps"
  grant for Termux.
- **`pm install` cannot work from the app**: installing needs
  `INSTALL_PACKAGES`, which only the shell and root identities hold. That is the
  documented requirement, not a measurement — the probe fails earlier, at "unable
  to open file".
- With Shizuku or self-adb, `adb install -r` makes installs *and updates*
  scriptable. This is the first place in §12 where shell-graded access buys
  something structural rather than diagnostic.
- Updates must come from the **same signing key**, so the keystore is the app
  fleet's identity: one per app or one per fleet, and never in the repository.

### 13.6 Talking to it, and what the channel leaks

- `am broadcast` **works from inside the app** — measured, "Broadcast
  completed" — and supports `--include-stopped-packages`, which the first trigger
  after install needs, because a never-launched app receives no broadcasts.
- Across UIDs there is no shared `$HOME`. Realistic channels are an exported
  receiver, a localhost socket with a bearer token, and shared storage. A
  `protectionLevel="signature"` permission is unavailable unless the workload app
  shares Termux's signing key, which we do not control; and `content` (the shell
  helper for provider calls) is not installed, so a `ContentProvider` cannot be
  driven from the shell at all.
- Therefore the trigger must be **safe to receive from anyone**: argument-free
  ("run your own job"), idempotent, rate-limited, with every secret kept on the
  Termux side. That also decides which jobs may be foreign — media/ZIM sync and
  cache pruning yes; anything touching `~/.ssh` or the keystore no.

### 13.7 What it buys, and what it does not

Buys: a real UID + SELinux boundary (the only kernel-enforced option in §12.4, at
a few megabytes instead of gigabytes), OS supervision and scheduling, a separate
LMK victim, its own permission set and Doze exemption.

Does not buy: cgroups or memory caps (LMK still rules), a shared filesystem,
secrets, or DAG *ordering* across apps — Termux stays the planner, and a workload
app can only report back by writing to shared storage or posting a notification.

Cheaper 80 %: `android:process=":w"` inside one app gives a separate address space
and a separate LMK target with no build complexity — and no security boundary at
all, since the UID and the SELinux domain are unchanged.

### 13.8 If adopted, what lands here

An `apk/` directory with a five-command `build.sh` taking `PKG=`, the `stubs/`
sources (the API surface as documentation), one manifest template (target 28, no
launcher activity, exported receiver plus foreground service,
`RECEIVE_BOOT_COMPLETED`), a git-ignored keystore path, and one paragraph fixing
the trigger contract. The manifest gains a `foreign` target naming the shim package, an
action and a payload id (§14), and `plan` marks the install as a human step — the same shape as the
`staged/` convention in §11.3.

Honesty note: no APK was built or installed in this session. Every package,
version and timing above is measured; the build sequence itself is the standard
one and is unverified end to end here.

## 14. Shim and payload: only the payload has to change

The question is whether each workload app must be *compiled* locally, or whether a
fixed launcher can carry a swappable payload — a UEFI-shim arrangement where the
shim is built once and the payload is data. Measured answer: **yes, and the split
is cleaner than the shim analogy suggests, except at one specific point** (payload
verification, §14.4).

### 14.1 The four costs, separated and measured

| what changes | what must run | measured |
| --- | --- | --- |
| the shim's Java code (once, ever) | `javac` + `d8` | 2.16 s for a trivial class; `d8` unmeasured |
| the shim's manifest/resources (rarely) | `aapt2 link` (+ `d8` only if the code changed) | unmeasured |
| **a new payload inside the APK** | repack + `apksigner` — **no javac, no d8, no aapt2** | `zip` is **absent** from the device (measured), so repack with `python3 -m zipfile` or install `zip` |
| **a new payload outside the APK** | nothing on the APK at all | file copy + hash |

The Java half is therefore a one-time cost, and the *repeat* cost is a payload
build. Measured on this device with `CGO_ENABLED=0 GOOS=android GOARCH=arm64
GOGC=50 -p=2 -trimpath -ldflags='-s -w'`:

| payload | cold build | warm rebuild | size | NEEDED entries |
| --- | --- | --- | --- | --- |
| hello (`fmt` only) | **27.6 s** | **1.7 s** | 1.77 MB | **0** — fully static |
| `net/http` touch | **44.0 s** | (not measured) | 3.80 MB | 0 |

Zero `NEEDED` is the important number: a Go static payload has no libc, no
`$PREFIX` path and no bionic version skew, so it runs from any directory that
permits execution, in any app's sandbox, forever.

### 14.2 The one hard constraint: the card is noexec

Measured mount options: the SD card, emulated storage, `Android/data` and
`Android/obb` are all `nosuid,nodev,noexec`. A payload **cannot be executed from
the card**. So the shim's load step is real work, and it is the analogue of the
ESP: read the payload from shared storage, optionally verify a hash, copy it into
the shim's own `filesDir` (executable only while the shim targets 28, §13.4),
`chmod 700`, then `execve`. `nosuid` also means no setuid trick can ever matter,
and the payload inherits the shim's UID — the shim's identity *is* the payload's
identity, which is exactly the relationship a shim has with what it loads.

### 14.3 Three payload tiers, measured

| tier | artifact | needs | caveat |
| --- | --- | --- | --- |
| **script** | text plus `/system/bin/sh` (310 KB, present) and `/system/bin/toybox` (present) | nothing | only toybox's command set; no compile, no sign, no install |
| **static native** | Go with `CGO_ENABLED=0`, 1.8–3.8 MB, 0 `NEEDED` | `go` 1.27.4 (installed) | prefix-free and self-contained; the sane default |
| **bionic C** | `clang` 21.1.8, target `aarch64-linux-android24` | nothing extra | **dynamic only**: `clang -static` fails (no `crtbegin_static.o`, no `libc.a`), and the output carries `RUNPATH=$PREFIX/lib`, so it must need *nothing but* system libraries (`libc`, `libdl`) — any libc++ use breaks inside a shim that cannot read Termux's prefix |

So the "clang + bionic" idea is real but constrained: a libc-only C payload works
(5.7 KB for the probe, `NEEDED` = `libdl.so`, `libc.so`, both from `/system/lib64`), and
anything above that has to be Go or a script. `/system/bin/dalvikvm` also exists,
so a *dex* payload tier is conceivable, but it would need `d8` and probably a
permitted SELinux domain — recorded as untested, not as available.

### 14.4 The shim is not a shim where it matters

- **Identity: the analogy holds.** Package name + signing key + UID + granted
  permissions are verified by PackageManager at install; updates require the same
  key, so the shim is the stable thing and the payload is data.
- **Verification: it breaks.** Nothing in Android checks a file the shim execs.
  A UEFI shim verifies its payload against a second key; here the chain of trust
  ends at the APK, and the payload is accepted because it exists. A pinned hash —
  hardcoded in the shim, or in a manifest Termux writes — restores the *accident*
  half of that guarantee and none of the adversary half: whoever can write the
  card can write a payload and its hash.
- **Revocation and rollback: absent.** No SBAT, no anti-rollback, no measured
  boot; an uninstall/reinstall yields a **new UID**, drops every grant, and wipes
  `filesDir`. So the shim must be installed once and only ever updated in
  place — which also means the keystore is a permanent, unbackuped asset (§13.5).

### 14.5 What this changes in the plan

- The install tap disappears from the per-workload cost: **one shim per device**,
  then N payloads are file copies. §13.5's friction survives only for the first
  install and for shim revisions.
- Payload delivery becomes DAG work that Termux can do itself: build → hash →
  copy to the card → notify the shim. It is a `disk` job plus an `extdisk` job,
  not a build-and-install ritual.
- The result channel becomes mandatory, and cheap: the shim writes exit code,
  duration and its own `wait4` peak RSS as JSON into shared storage, and the
  planner reads it — the same `staged/` direction as §11.3, reversed.
- The manifest's `foreign` target names **one shim package, one action and a
  payload id** rather than a package per workload — one target type, N payloads.
- The residual cost is disk, not CPU: the shim's `filesDir` copy means 2–4 MB
  of app data per payload while it runs (the card stays the master copy).

### 14.6 Cross-compilation: exactly one ABI, and what "valid" means

Measured, because "can this host emit a valid cross-compiled payload" turns out to
be ABI-dependent rather than toolchain-dependent.

| what | result |
| --- | --- |
| `clang --target=armv7a-linux-androideabi30 -c` / `--target=x86_64-linux-android30 -c` | **compile OK** — the objects are correct (`Machine: ARM`, `X86-64`) |
| **link** the same for armv7 / x86_64 | **fails** — no `libclang_rt.builtins.a` for x86_64, no `libunwind.a` for armv7 |
| **link** for the native ABI, any API level | **OK for 21, 24, 28, 30, 33** — 5.8–5.9 KB, `NEEDED` always just `libdl.so`, `libc.so` |
| Go pure static `GOOS=android GOARCH=arm64` | **OK** — 27.6 s cold, 1.77 MB, 0 `NEEDED` |
| Go pure static `GOARCH=amd64 / 386 / arm` | **refused**: "requires external (cgo) linking, but cgo is not enabled" (0.09 s) |
| Go **with cgo**, arm64 | **OK** — 15 s, 1.60 MB, but **dynamically linked** (`libdl.so`, `libc.so`, `RUNPATH=$PREFIX/lib`) |
| Go with cgo, armv7 | **fails** — no `libunwind.a`

So: this host can produce runnable Android artifacts for **exactly one ABI,
arm64-v8a** — the one the device is. It can *compile* objects for the others but
not *link* them, because the missing pieces are per-ABI linker runtimes
(`libclang_rt.builtins.a`, `libunwind.a`) rather than headers or a sysroot, and
Termux ships them only for its own ABI. Go obeys the same limit for a different
reason: `android/arm64` links internally and is genuinely prefix-free, while every
other Android port demands cgo and external linking, which then dies on the same
absent runtimes. Adding `cgo` on arm64 works but converts a static payload into a
dynamic one, so the static Go build stays the default.

The API level is a **`--target` flag, not a sysroot**, and does not restrict
linking: 21 through 33 all link against the same header set (android24) and differ
only in size. A newer symbol is therefore a *runtime* risk that the compiler
cannot catch — which is an argument for keeping payloads to plain POSIX calls.

One consequence worth stating plainly, because it dissolves the question: **an APK
is ABI-neutral**. `aapt2`, `d8` and `apksigner` are Java, and a shim whose payload is
a *file* carries no `lib/<abi>/` directory at all, so there is no such thing as a
cross-compiled APK here — the shim is universal and the payloads are per-device
artifacts. That is also the escape hatch for other ABIs: a **script** payload needs
only `/system/bin/sh` and is ABI-free, so an x86_64 Android (emulator, VM) can run
the same fleet with script payloads even though this host cannot build a native
one for it.

### 14.7 As an NDK, and what "a typical app" would need

Two questions with different answers: a **partial NDK for one ABI — yes**; a
**typical Java/Kotlin app with native dependencies — no**.

**JNI libraries, measured.** `jni.h` is present (`$PREFIX/include/jni.h`, from the
JDK), so a real JNI library can be produced here:

| what | result |
| --- | --- |
| C JNI, `clang -shared -fPIC` | **5.4 KB**; `NEEDED`: `libdl.so`, `libc.so` |
| C++ JNI (`std::string`) | **42.9 KB**; `NEEDED`: `libc++_shared.so`, `libdl.so`, `libm.so`, `libc.so` |
| `-static-libstdc++` | **fails** — no `libc++.a` or `libc++abi.a` is shipped, and the flag resolves to `-lc++_shared` |

Both carry `RUNPATH=$PREFIX/lib`, which is a Termux artifact to strip before shipping.
The C++ case needing `libc++_shared.so` is not a defect: NDK apps bundle it in
`lib/<abi>/` anyway, and `libc++_shared.so` is present here (1.42 MB). Whether
Termux's copy is ABI-compatible with what an app expects from the NDK is untested.

**The "typical app" toolchain, sorted by where it actually stands.**

| part | state |
| --- | --- |
| `java`, `javac`, `keytool` | installed |
| `aapt2` 964 KB, `d8` 14.7 MB, `apksigner` 1.07 MB, `zip` 3.0, `cmake` 11.2 MB, `ninja` 84 KB, `make` | in the index, not installed (this corrects §14.1 on `zip`: absent *installed*, available *installable*) |
| `gradle` **132.6 MB**, `kotlin` **87.7 MB** | in the index; both depend on `openjdk-21`, which is installed |
| `sdkmanager`, `android-sdk`, `build-tools`, `platform-tools`, any NDK, AGP | **not in the index and not obtainable from apt at all** |

The wall is therefore not the compilers. It is, in order:

1. **AGP and the SDK** live on Google's Maven and dl.google.com — the Android Gradle
   Plugin, the `compileSdk` platform jars and build-tools have no apt package. A
   Gradle build without them is a Gradle build of nothing.
2. **Memory.** Measured: the JVM's ergonomic `MaxHeapSize` on this device is
   **945 MB** (it tracks `MemAvailable`, ~1.06 GB now). Gradle plus AGP conventionally
   wants 1.5–2 GB and `kotlinc` alone wants most of a gigabyte; this is the same OOM
   wall that forced `-p=2 GOGC=50` for Go, one layer up.
3. **Host architecture.** Official NDK releases ship **x86_64-linux** host binaries
   (an inference from the NDK's layout — there is no NDK here to inspect), which
   cannot execute *natively* on aarch64 Android — though §15.2 shows they do run
   under qemu-user at roughly twice the cost; and per §14.6 the per-ABI linker
   runtimes are missing anyway, so arm64 is the only linkable target.

Then the distinction the question actually turns on:

- **Prebuilt `.so` dependencies** — the common case, four ABIs from Maven — are
  never *built*; they are **bundled**, and `arm64-v8a` alone is enough for one device.
  No NDK required.
- **Source dependencies** (ffmpeg, openssl, libpng) must each be cross-built against
  a sysroot. Against the Termux sysroot they come out linked to `$PREFIX` — usable
  from the shell, **not** loadable in an app sandbox — so this is precisely where
  "random native dependencies" stops.
- **Kotlin** is the one JVM-side door still ajar: 88 MB, then `kotlinc` on
  `openjdk-21` against a 945 MB ceiling — tight but conceivable for a dependency-free
  file. What Kotlin is normally *for* (coroutines, KSP, kapt) needs Gradle and is out
  of reach.

So the reachable ceiling is a **dependency-free, Java-only, arm64-only** app, which is
exactly the shim of §14 and nothing beyond it. The "typical app" needs three things
this host lacks — Maven/SDK artifacts, two gigabytes of heap, and an x86_64
toolchain — and §15 measures that all three are obtainable rather than impossible.

### 14.8 Verdict

Only the payload needs building, and even that can be a shell script: script tiers
need nothing, Go static tiers cost 1.7 s warm and 2–4 MB, and clang/bionic is
limited to libc-only C because this host has no static bionic. The shim's Java
half is compiled once for the life of the device. What the analogy gets wrong is
verification — the shim loads what it finds — and what it gets right is identity:
the APK signature is the only thing that cannot change without a reinstall and a
new UID.

## 15. Can a conventional application be built here, slowly?

"Conventional" means what Android Studio produces: Gradle + AGP + the SDK +
Maven-resolved dependencies + Kotlin, with native code optionally via the NDK.
The answer is **yes in principle, no in comfort**, and — after measuring each wall
rather than assuming it — the environment is **not architecturally too restrictive;
it is resource-restrictive**. Three things I had marked as hard stops turn out to be
soft. §14.7 is corrected accordingly.

### 15.1 The audit, artifact by artifact

| component | source | host arch | state here |
| --- | --- | --- | --- |
| JDK 21 (`java`, `javac`, `keytool`) | apt | aarch64 | **installed** |
| Gradle 9.9.2 (132.6 MB) | apt | Java | installable |
| Kotlin 2.4.21 (87.7 MB) | apt | Java | installable |
| `aapt2` 16.0.0.4-4 (964 KB) | apt | **aarch64 build** | installable |
| `d8`, `apksigner` 37.0.0 (14.7 / 1.07 MB) | apt | Java | installable |
| `cmake` 4.5.1, `ninja` 84 KB, `make` | apt | aarch64 | installable |
| `adb` (android-tools 37.0.0p1-3, 2.37 MB) | apt | aarch64 | installable |
| **`android.jar` / platform-30** (~60 MB) | dl.google.com | **pure data** | fetchable |
| **AGP, R8, kotlin-gradle-plugin, transitive Maven** (~150–400 MB) | Google Maven | Java | fetchable |
| **build-tools natives** (`zipalign`, `aidl`, `aapt2`) | dl.google.com | **x86_64 ELF** | runnable under qemu (§15.2), or replaced (§15.3) |
| **NDK r26+** (2–3 GB) | dl.google.com | **x86_64 ELF only** | runnable under qemu (§15.2), unverified |
| `sdkmanager` | cmdline-tools | bash + jar | fetchable, arch-neutral |

Nothing in that table is *missing* in an unfixable way. The only genuinely native-host
dependencies are the build-tools and NDK binaries, and those are the ones §15.2 tests.

### 15.2 The three walls, each measured and each downgraded

**Wall 1 — network: reachable, fast, and merely volumous.** `curl -sI` against
`dl.google.com/android/repository/repository2-3.xml` returned **HTTP/2 200 in
0.30 s**. So the SDK and Google Maven are not blocked or slow to answer; the cost
is quantity — roughly 0.5–1 GB for a first conventional build including an NDK.
That is a bandwidth-and-expiry problem (already a known constraint on this device),
not an architectural one.

**Wall 2 — host architecture: not a wall at all.** `qemu-user-x86-64` 11.1.3 is in
the index (571 KB download, 2.26 MB installed; pulls `glib`, `libgnutls`, `libpixman`,
`libdw`, `libandroid-shmem`). Measured end to end: a static x86_64 Linux binary was
built here with Go (`GOOS=linux GOARCH=amd64`, **24.4 s**, 1.51 MB), refused by the
kernel natively (the shell tried to parse it), and executed by
`qemu-x86_64 ./hello-amd64` in **0.365 s wall including emulator startup**, printing
"running: linux/amd64". Emulation is also *correct* and cheap on compute: an
identical integer benchmark ran **1.9× slower under TCG on one run and 4.4× on
another**, with the same result hash; core placement between the 4× A53 and 4×
A73 clusters dominates the spread, so read it as 2–5× (§16.2 has the
controlled four-way comparison). So the NDK's x86_64 clang,
`zipalign` and `aidl` are executable here. Compiler workloads will cost more than that
(process spawns, I/O, multithreading), but the plausible range is **2–5×**, not
the order of magnitude that would make it pointless. Not measured: clang itself,
because no NDK is present.

**Wall 3 — memory: tight, not prohibitive.** `-Xmx1400m` is honoured (the JVM is not
clamped by `MemAvailable`), and a JVM held **600 MiB live in 1.7 s** with 1.19 GB of
swap still free afterwards. One earlier probe OOM'd at 512 MiB inside a 900 MB heap,
which is G1 humongous-allocation fragmentation (1 MiB arrays land on region
boundaries), not a device limit — so heaps must be sized generously, not minimally.
The real ceiling is what the LMK will tolerate for the *whole* process group, which
is why §7 keeps builds serial and `GOGC` low for Go.

### 15.3 What a conventional build would actually require

1. `pkg install gradle kotlin aapt2 zip ninja cmake` — 132.6 + 87.7 MB plus a few
   hundred kilobytes; `unzip` is already present.
2. An SDK directory assembled by hand: `platforms/android-30/android.jar` from
   dl.google.com (data only), and `build-tools/<ver>/` populated with the apt `aapt2`
   plus jars for `d8` and `apksigner`. AGP can be pointed at an external aapt2
   (the `android.aapt2FromMavenOverride` property exists for exactly this, unverified
   here). `zipalign` may not even be needed: modern AGP aligns through its own
   Java zip implementation rather than the old native tool — an inference, and the
   fallback is a 40-line Python aligner.
3. AGP + R8 + the Kotlin plugin from Google Maven, plus whatever the project's
   dependencies pull in. This is the bulk of the traffic and the bulk of the risk.
4. `gradle.properties` tuned for one slow device:
   `org.gradle.jvmargs=-Xmx1500m -XX:MaxMetaspaceSize=512m`,
   `org.gradle.workers.max=1`, `org.gradle.parallel=false`, and Kotlin's
   incremental compilation off to avoid a second daemon.
5. Kotlin specifically may need to run under emulation or be dropped: 87.7 MB plus
   a compiler that wants most of a gigabyte, inside the same heap as Gradle.

Predicted, and clearly marked as prediction: **20–60 minutes for a first build** on a
warm enough link, **2–5 minutes incremental**, **1.2–1.6 GB RSS** — which is exactly
where the LMK starts taking an interest. Painful, not impossible.

### 15.4 Verdict by class

| class | verdict | basis |
| --- | --- | --- |
| dependency-free Java shim | **yes — measured** | §13, §14 |
| conventional app, no native code | **probably yes, slowly — unverified** | all three walls downgraded; needs ~0.5 GB of traffic and a 1.5 GB heap |
| conventional app with NDK-built deps | **yes in principle, painfully** | x86_64 toolchain only under qemu (1.9× measured on compute), arm64-only linking (§14.6), per-dependency sysroot builds still the long pole |
| multi-module Kotlin with kapt/KSP | **no practical chance** | annotation processing + Kotlin daemon + AGP in one 1.5 GB heap on a phone that swaps at 2.6 GB |

### 15.5 Is this environment too restrictive?

**Not architecturally.** Every piece a conventional build needs is either data
(`android.jar`, Maven jars), an apt package (`gradle`, `kotlin`, `aapt2`, `cmake`, `adb`),
or an x86_64 ELF that runs under a 571 KB emulator at about twice the cost.
What differs from an average mobile build environment is not capability but
**throughput and headroom**: a typical workstation has 4–8 x86_64 cores, 16–32 GB of
RAM and a warm Gradle cache; this device has 8 slow ARM cores, ~1 GB available,
2.6 GB of swap, a cold cache and a metered link. The honest delta is *hours per
build and hundreds of megabytes per attempt*, on a device whose LMK is one bad
compile away from killing the terminal that started it.

The one place the environment is genuinely restrictive is the one that started this
whole thread: there is no native toolchain for anything but arm64 (§14.6), and no
official NDK that runs unemulated. That is a real limit — it just costs 1.9×, not
impossibility.

### 15.6 What would settle it empirically

1. `pkg install gradle aapt2 zip` (≈135 MB).
2. Fetch `platforms;android-30` (~60 MB) and AGP + R8 from Google Maven.
3. A single-module "hello" project, no Kotlin, with
   `android.aapt2FromMavenOverride` pointing at the apt `aapt2`.
4. `gradle --no-daemon --max-workers=1 assembleDebug` with the §15.3 heap settings.
5. Record: wall time, peak RSS, whether the daemon survived, and whether the
   resulting APK installs via `termux-open`.

If step 5 passes, "conventional app: yes, slowly" moves from inference to
measurement, and the cost is one afternoon and about 200 MB of traffic.

## 16. Emulation, proot, and the price of a "POSIX arm64 environment"

The question — would emulating a POSIX arm64 environment beat proot, and is the
x86_64 emulation necessary — has a crisp answer once the three options are measured
side by side on this hardware. All four configurations ran the *same* Go program:
a 300-million-iteration integer loop, then 20 000 `stat` calls.

| configuration | cpu loop | 20k syscalls | vs native (cpu / syscall) |
| --- | --- | --- | --- |
| **native arm64** (baseline) | 0.330 s | 0.289 s | 1.0× / 1.0× |
| **proot** (same ISA, ptrace path rewriting) | 0.333 s | **12.367 s** | 1.01× / **43×** |
| **qemu-aarch64** (arm64 on arm64, TCG, no KVM) | 2.048 s | 1.472 s | **6.2×** / 5.1× |
| **qemu-x86_64** (x86_64 on arm64, TCG) | 1.463 s | 1.221 s | 4.4× / 4.2× |

### 16.1 There is no "emulating arm64" here

The CPU is arm64. Running arm64 under `qemu-aarch64` is emulating a machine on
itself: measured **5–6× slower with zero compatibility gain**, because the only thing
it adds is a CPU model nobody needs. The same is true of a full VM: with `/dev/kvm`
absent (established in §1), `qemu-system-aarch64` runs under TCG and pays the same
5–6× while adding a kernel to boot. A *native-speed* isolated arm64 POSIX environment
requires KVM, which this device does not expose to apps, so it does not exist here
at any price.

What does exist, in increasing cost: **native Termux** (1×, shares the UID and the
filesystem), **proot** (native compute, catastrophic syscalls, no isolation), and
**a TCG VM** (5–6×, real isolation, QEMU's device model as attack surface).

### 16.2 proot is fast at arithmetic and brutal at syscalls

`proot` does not emulate instructions; it rewrites paths by intercepting syscalls.
Hence 1.01× on pure computation and **43× on `stat`** — 20 000 calls going from
0.29 s to 12.4 s. Every build, sync, or file-tree walk is syscall-bound, so this
is the worst possible place to put a compiler: a proot-distro toolchain would spend
almost all of its time in ptrace, not in code generation. For the workloads in §3
(the DAG's copy/prune/sync steps) the same arithmetic applies in miniature: proot
would make them noticeably slower than the plain Termux commands they already are.

Safety is the opposite story: **proot is not a boundary**. Same UID, same kernel,
same SELinux domain, escape by design rather than by exploit. It is a compatibility
device, which is exactly what §12 already concluded for `proot-distro`.

### 16.3 Is x86_64 emulation necessary?

**For running anything we build: no.** §13's shim is aarch64; `aapt2` from apt is an
aarch64 build; `d8` and `apksigner` are Java; §14's payloads are native arm64 or
shell scripts. Nothing in that path touches an x86 instruction.

**For building with x86-only toolchains: yes, and only there.** The official NDK and
the SDK's build-tools natives exist as x86_64 Linux ELF only (§15.1), and this host
cannot execute those natively. So the 571 KB emulator buys exactly one thing: the
ability to run somebody else's x86_64-hosted compiler. That is a real capability,
but it is a capability the architecture in §13–§14 does not need.

So the ordering is: **native aarch64 everywhere it exists** (it does, for everything
we build), **qemu-user-x86_64 only as a rescue** for an x86-only tool, and **neither
proot nor arm64 emulation at all** — the first is a syscall tax with no safety, the
second is a slowdown with no purpose.

### 16.4 What this implies for the two-state backend

The §3 measurement that `sh -c 'exit 0'` costs 24–27 ms and a Python start 72–110 ms
is unaffected by this: those are native. The rule the numbers support is simply
*never put a compatibility layer under a frequently-started command*, whether that
layer is proot, a VM, or an emulator. If a step ever needs a different userland, it
belongs in a `foreign` target (§12.6) or behind a `flock`-guarded one-shot, not under
the scheduler's normal path.

## 17. A full-system VM: how complete, how safe, and how to not OOM

Three separate questions — completeness, safety against untrusted payloads, and the
memory story — with different answers. First a correction: **no full-system emulator
is installed** here. §15 and §16 measured the *user-mode* emulator (`qemu-x86_64`),
which translates syscalls for a binary sharing our kernel. System mode is a different
package and a different thing.

### 17.1 What it would be, and what it costs to have

`qemu-system-x86-64-headless` 11.1.3 is in the index: 2.69 MB download, 25.7 MB
installed — but it drags **20 packages even with `--no-install-recommends`**
(`qemu-common` alone is 21.1 MB download and **342 MB installed**, plus `jack2`,
`gstreamer`, `libspice-server`, `libusbredir`, `libssh`, `libnfs`, `dtc`), and 32 with
recommends (mesa, vulkan, opengl). No `seabios` or `ipxe-qemu` is packaged, so the
firmware has to come from qemu-common's blobs — unverified.

Completeness, unambiguously: **yes, it is a full computer.** System mode emulates a
whole PC — a CPU with MMU, PCI, virtio devices, IDE/SCSI, serial, VGA and slirp
NAT — and can boot an unmodified x86_64 operating system. That is precisely the
difference from §16's emulator, which runs a single process against *our* kernel.

The price is speed: with no `/dev/kvm` (§1) everything is TCG. Measured TCG factors
here are **4.4× (x86_64) to 6.2× (arm64)** on compute and 4–5× on syscalls in
*user* mode; system mode adds MMU/TLB emulation, device models and kernel idle
paths, so expect **an order of magnitude or worse** — a minimal Linux boot in
minutes rather than seconds. Prediction, not measurement: nothing here has booted an
OS.

### 17.2 Safety against untrusted payloads: three layers, ranked honestly

1. **The guest kernel is a real boundary.** The payload must compromise the guest
   OS before it can touch QEMU, and that is far stronger than proot (§16.2, no
   boundary at all) or than any chroot/namespace trick (unavailable here anyway:
   §1's `unshare -U` gives EINVAL and `-m`/`-p` give EPERM).
2. **QEMU is not a hardened hypervisor.** Its device models are a large C surface
   with a long CVE history, and the dependency list above is the worst of it —
   SPICE, USB redirection, slirp, gstreamer. The defence is subtraction:
   `-nodefaults -display none -net none`, no USB, no SPICE, no VGA, one
   `virtio-blk` disk and a `virtio-serial` console, and `-sandbox on` if the build has
   seccomp support (unverified). This host's own seccomp filter is already mode 2
   with `CapEff 0`, so the VM cannot gain capabilities even if it tried.
3. **The blast radius of a successful escape is our own UID.** QEMU runs as
   `u0_a277` inside `untrusted_app`; an escape lands with `~/.ssh`, the keystore
   and the dotfiles — the exact things a sandbox is supposed to protect. So a VM
   inside Termux is **containment of intent, not a security boundary** against
   adversarial code, which is what §12 concluded for TCG QEMU in the first place.
   Adversarial payloads belong in a second app or second user (§12.4, §13), where
   the UID and SELinux do the separating.

Channels that *do* shrink under the VM: no `/dev/kvm`, no device passthrough, no
network except slirp's NAT (seen from outside as the app's own connection), and the
Android seccomp filter still applies to the emulator process.

### 17.3 "File swapping in userland": no — but file-backed RAM, yes

**Swap cannot be added.** Measured: `/system/bin/swapon` and `swapoff` exist in toybox,
and invoking them **dies with exit 159 — signal 31, SIGSYS** — because Android's
seccomp filter kills the syscall instead of returning an error; `/proc/swaps` is
EACCES, so even inspection is denied; and `swapon(2)` would need CAP_SYS_ADMIN
against a `CapEff` of zero. The 2.5 GB of zram swap the phone already has is
kernel-managed and immutable.

**The goal is still reachable**, and the mechanism is the page cache rather than the
swap subsystem — which also sidesteps seccomp, because it needs no privilege:

    qemu-system-x86-64-headless \
      -accel tcg,tb-size=32 -smp 1 -m 768 \
      -object memory-backend-file,id=mem,size=768M,mem-path=/data/.../guest.ram,share=on \
      -machine q35,memory-backend=mem \
      -nodefaults -display none -net none -serial mon:stdio \
      -drive file=/data/.../guest.qcow2,if=virtio,format=qcow2

Guest RAM then lives in a file on ext4: under pressure the kernel writes those
pages back and evicts them, so the guest gets slower instead of the LMK killing
QEMU. Measured on this device: `/data` write+fsync **186 MiB/s**, read-back
**537 MiB/s**; `MAP_SHARED` page touches **172 MiB/s** with a 0.25 s `msync` per
256 MiB — and after touching 256 MiB of a shared file, `MemAvailable` was still
~1.07 GB while RSS showed 264 MiB of *reclaimable* cache. The pages really do stay
evictable.

Two siting rules and three knobs:

- **Put the RAM file on `/data`, never the card.** The card measured **48 MiB/s**
  write (≈4× slower) and is a `noexec,nosuid` FUSE mount — the wrong thing to mmap.
- Keep `-m` small (512–768 MB), `-smp 1`, and `-accel tcg,tb-size=32` so the
  translation buffer does not itself become the memory hog; add
  `-device virtio-balloon` if the guest can hand pages back, and `prlimit --as=`
  as a hard backstop the guest cannot talk its way out of.
- Accept the consequence: the RAM file is not crash-consistent. Treat it as
  discardable on boot and require the guest to do its own `os.replace` +
  `fsync` — the same stance §4 takes for the host.

So the honest summary of this section: **swap is refused by the platform, but "slow
rather than OOM" is achievable** — the file-backed RAM file *is* your swap, implemented
by the page cache at 172–537 MiB/s instead of by the swap subsystem, which is a trade
this device can actually pay.

## 18. Local benchmark: what this system actually costs on this device

Everything below was measured on this phone, on the deployed dotfiles (the four rc
files are byte-identical copies of `src-dotfiles.sh`, verified with `cmp`), with the
whole chain sourced exactly as a new terminal sources it. Nothing in the repo was
changed: the optimisations in §18.6 were measured by copying `profile.d/` to a
scratch tree and pointing `DOTFILES` at it (the loop honours that override, defaulting
to `$HOME/dotfiles`), so every number is a *proposal*, not a deployment.

### 18.1 Method, and why the numbers are min-and-median

Each configuration was run 4–9 times; reported as **min** (least contended, the
honest "how fast can this be") and **median** (what it feels like). The spread is
large — min and median differ by up to 50 % — because this is a 4×A53 + 4×A73
big.LITTLE part and a single run lands wherever the scheduler puts it (§15.2 has
the same effect on the emulation numbers). Any single measurement here is worthless;
only the min-of-many is stable.

`strace` is not installed, so there are no exec counts: cost is attributed by
**ablation** — remove one snippet from the scratch tree, re-measure the whole
startup, and report the difference. That is why several rows are slightly negative.

### 18.2 The exchange rate: processes are precious, everything else is free

| operation | min | median |
| --- | --- | --- |
| `/system/bin/true` (one bionic exec) | **29 ms** | 41 |
| `sh -c exit 0` | 26 | 41 |
| `stat` (either libc, one file) | 41 | 45 |
| `git status --porcelain` | 43 | 48 |
| `df /data` / `find` over 50 files | 73 | 77 |
| `flock -n FILE true` / `timeout 5 true` | 75 | 81 |
| `python -c pass` | 124 | 130 |
| `node -e 0` | **380** | 424 |
| 100 × `[ -x /nonexistent ]` in zsh, vs 100 × on a real file | **0** | 0 |

The rule this establishes, and the one every recommendation below follows: **a
fork+exec costs 25–45 ms and a heavy interpreter 124–380 ms, while in-shell work —
glob expansion, `[ -x ]`, parameter expansion, arithmetic, `printf` — is free at this
scale.** 100 filesystem tests cost less than nothing measurable; one `stat` costs
41 ms. Optimising shell logic here is pointless; the only lever is the number and
weight of processes.

### 18.3 Startup: 275 ms, of which two files are 200 ms

| configuration | min | median |
| --- | --- | --- |
| `zsh -f -c :` (no rc) | 42 | 44 |
| `zsh -f -i -c exit` (no rc) | 41 | 44 |
| **zsh -i, dotfiles** | **269** | **326** |
| **bash -i, dotfiles** | **270** | **332** |
| bash -l -i, dotfiles | 323 | 374 |
| zsh -i, only `10_env.sh` + `80_path.sh` | 38 | 48 |

Per-snippet ablation, zsh (removing one file and re-measuring the whole startup):

| snippet | cost in situ |
| --- | --- |
| `70_history.zsh` (`atuin init` + the `--version` probe) | **+100 ms** |
| `40_completion.zsh` (`compinit` + fpath + writes) | **+50 ms** |
| `10_wsl2.sh` | +1.9 (noise) |
| `72_hardening.sh` | +0.8 (noise) |
| `10_env.sh`, `20_core.bash`, `40_completion.bash`, `60_kubeconfig.sh`, `70_history.sh`, `70_history.bash`, `70_moratorium.sh`, `80_path.sh`, `90_navigation.zsh` | **0 (within noise)** |
| completion + history both removed | 74 |
| floor: two snippets only | 38 |

So **eleven of thirteen snippets are free, and two are 73 % of startup.** Under bash
the same file is worse — `70_history.bash` (bash-preexec + atuin) costs **≈198 ms**
(bash -i goes 270 → 71 without it; 40 with both hot snippets gone), because
bash-preexec installs its own `DEBUG`/`PROMPT_COMMAND` machinery on top of the spawn.

Also worth recording: the comment in `40_completion.zsh` cites "~28 ms net in zsh"
for `mise activate` (DR-045, profiled 2026-11-18). That path does not run here at
all — no mise, no brew, no uv, no kubectl — which is why startup is 275 ms and not
much worse. The snippets are written for a workstation; this phone pays only the
atuin and compinit parts of that price.

### 18.4 The real cost is not startup, it is every command you type

| commands piped into an interactive zsh | wall time | per command |
| --- | --- | --- |
| 1 | 473 ms | — |
| 6 | 1035 ms | ≈128 ms |
| 20 | 2395 ms | **≈106 ms** |
| 6, with `70_history.zsh` removed | **173 ms** | ≈0 |

That is the largest number in this document. Atuin's zsh hook runs
`atuin history start` **synchronously in `preexec`, before the command executes:
measured **125 ms** for one call, 226 ms for two in a row, against a pure-start
floor of 68 ms (`atuin --version`), so it is ~57 ms of spawn plus ~57 ms of SQLite.
Every Enter pays it. Twenty commands cost 2.1 s of pure waiting — eight times what
opening the terminal cost.

With atuin's own daemon running (`daemon.enabled`, `atuin daemon start`) the same call
drops to **67 ms** — the socket wins the SQLite half, but the process spawn half
remains, because the shell still has to exec `atuin` to talk to it.

### 18.5 Three optimisations that were tried and did not pay

- **`zcompile`**: precompiling the rc and all snippets (14 `.zwc` files) changed
  startup from 275 to 277 ms. Parsing a 5 KB rc is free; there is nothing to save.
- **Removing the per-shell run-guard write** (the `read` + `mkdir -p` + `printf > file`
  in `df_startup`): 274 vs 269 ms, i.e. noise. The `df_due`/`df_stamp` machinery is
  cheap — it is the *shape* a run-guard should have here, and it needs no change.
- **`compinit -C`** (trust the existing dump instead of validating fpath mtimes) does
  pay, but only **36 ms** (269 → 233), against a cold `compinit` of 124 ms and a
  warm one of 79 ms.

One measurement *did* pay in the startup path: removing the allowlist's
`"$cand" --version` verification spawn in `70_history.zsh` (keeping the `[ -x ]` and the
`command -v mise` gate) took startup **269 → 225 ms**, a 44 ms saving from deleting
one line — the same line that, on a host without atuin, would run zero times, and
that here duplicates a check the very next spawn performs anyway.

### 18.6 The ranked gains, with the arithmetic

1. **Make history capture asynchronous (or native). — ~106 ms per command.**
   Roughly 10× the total startup win, and it compounds: 20 commands ≈ 2.1 s. Three
   options, in increasing order of change: the atuin daemon (−58 ms/command, one
   config key plus a supervised daemon — which is exactly what §3's "runit is a
   restart supervisor, not a job executor" is for); dispatch the hook with `&!` so
   the shell never waits (needs care: ordering and `$?` capture break); or keep
   `atuin` for search but capture with zsh's own `inc_append_history` and import on
   demand (0 ms/command, at the cost of DR-016's single-store guarantee).
2. **Delete the `--version` probe in `70_history.zsh`. — 44 ms per shell,** one
   line, no semantic change (the `init` spawn that follows is the real probe).
3. **`compinit -C` with a dump that is regenerated by the run-guard. — 36 ms per
   shell,** and it fits the existing `df_due` design: refresh the dump when stale,
   trust it when not.
4. **Everything else: nothing.** The remaining eleven snippets, the run-guard, and
   `zcompile` are all at or below noise. Startup after 1–3 lands near **171–225 ms**
   (measured: all three together = 171 min / 225 median), and the floor stays the
   interpreter itself at 38–44 ms. Even a perfect constellation leaves ~200 ms of
   atuin+compinit; that is the price of the features, not of the plumbing.

### 18.7 What the same exchange rate means for the orchestration system

The cost model transfers directly, and it should temper the DAG's shape:

| step kind | cost |
| --- | --- |
| in-shell builtin work (the whole `df_due`/`df_stamp` path) | ≈0 |
| one `sh -c` step | 26–41 ms |
| one `flock`-guarded `sh` step | 75–81 ms (the lock alone is a process) |
| one `git` step, one `df` step, one `find` step | 43–77 ms |
| one Python step | 124 ms |
| one Node step | 380 ms |
| doc gate (`node docs/spec-check.mjs`) | 528 ms |
| `shellcheck` on one file | 126 ms |

A 20-step plan written as 20 shell steps spends **0.8–1.6 s on forks alone**, before
any work; written as one Python process it spends 124 ms of startup and then
nothing. That is the concrete argument for the "one process per pass, not per step"
rule, and for keeping `flock` acquisition *inside* the batch rather than around it.
It also says the aggregator is right to keep the orchestrator off the startup path
entirely (§3): if a `node` or `python` gate ever lands in an rc file, every terminal
pays 124–380 ms for a check nobody asked for.

### 18.8 Honest limits of this measurement

- **No exec counts.** `strace` is absent and `/proc/<pid>/task/<tid>/children` is missing
  (§1), so attribution is by ablation, and two snippets that interact (completion
  writing `fpath` before `compinit` reads it) cannot be separated cleanly.
- **Piped stdin is not a terminal.** Line editing, prompt rendering and
  `zle` are excluded, so real interactive cost per keystroke is *not* measured;
  §18.4 measures hook cost only.
- **One thermal state, one device, no repeat across reboots.** Cold page cache was
  not controlled: the first runs of any binary were slower, which is why mins are
  reported rather than means.
- **The checkout is not the documented system.** `config/upkeep/jobs.json` and
  `bin/upkeep-everything-2.py` are untracked working-tree files, not committed
  history, and `lib/dotfiles.sh` referenced by the docs is absent (§10), so a
  fresh checkout has no orchestrator to measure; only its primitives are local
  (§18.7).

## 19. Which parts belong in one process, and what a fork is worth

§18 established the exchange rate (a fork is 25–47 ms, in-process work is free).
This section applies it to the design: what must be a process, what must not be, and
whether the answer survives on hardware that is not a 2019 midrange phone.

### 19.1 Three categories, and the rule that assigns them

- **(a) Inherently a process — the payload.** `git`, `rsync`, `node docs/spec-check.mjs`,
  `aapt2`, `go build`, `clang`, a Python tool. There is no in-process version of
  these, and the fork *is* the work: one process, unavoidable, priced in.
- **(b) Inherently in-process — the supervisor.** Graph resolution and next-node
  selection, the capacity ledger over declared constants, due-gating arithmetic,
  retry/backoff bookkeeping, state transitions, log formatting, quiesce decisions,
  report assembly. This is pure computation and file I/O; it has no business
  spawning anything.
- **(c) Either — decided by fork count.** "Read a stamp, compare two integers, write
  a stamp" is free as a builtin or a library call and 40 ms per action as
  `date`/`stat`/`mkdir`. Same semantics, 40× the price.

The rule that follows: **fork for the tool, never for the bookkeeping.**

### 19.2 The mapping for this system

| component | home | why |
| --- | --- | --- |
| capacity allocator (§3, declared constants) | library inside the supervisor | pure arithmetic, no I/O |
| `plan` subcommand | supervisor, one process per invocation | output is small; must not fork per node |
| `run NAME` | **one supervisor process per pass** | the pass is the unit of work, the step is the leaf |
| per-run token (`flock`) | one acquisition per pass, inside the batch | 75–81 ms per acquisition, so once not per step |
| backend probe (`df`, `stat`) | supervisor, batched once per pass | 41–77 ms each; per-step probing is the classic mistake |
| due-gating (`df_due`/`df_stamp`) | shell builtins, as it already is | measured ≈0 in situ (§18.5) |
| quiesce | supervisor writing one flag file | must not fork |
| backend matrix | data in the manifest, two states | no logic to place |
| notification (`termux-notification`) | one fork at the end of the pass | 1 fork/pass is free at this scale |
| `git`, `rsync`, `pkg`, builds, doc gate | one fork each, as payload | category (a) |
| the shell startup hook | shell, builtins only | §18: 11 of 13 snippets are 0 ms; anything that forks is 100 ms |

### 19.3 Measured: 20 steps, five implementations

Same 20 no-op steps, same bookkeeping (append a line per step, keep a running
count), min of 3–5 runs:

| implementation | total | per step | note |
| --- | --- | --- | --- |
| shell, 5 bookkeeping forks + 1 payload fork per step | **3163 ms** | 158 | `flock` + `mkdir` + `printf` + `date` + `stat` |
| shell, builtins only, 1 payload fork per step | **578–627 ms** | 29–31 | the fair shell implementation |
| C supervisor (RSS 1.8 MB), 20 forks | 622 ms | 31 | |
| Go supervisor (2.03 MB binary), 20 execs | 624 ms | 31 | starts in **25 ms** |
| Python supervisor (RSS ~15 MB), 20 execs | 727–832 ms | 36–42 | starts in **124 ms** |
| Python, bookkeeping only, no execs | 128 ms | — | 15 ms of work in a 124 ms start |

Three things to read out of that table:

1. **The bookkeeping forks are the entire problem.** 3163 → 627 ms is a 5× swing
   from moving *only* the bookkeeping into the process.
2. **Language choice is second order.** Per-step, C/Go/shell are indistinguishable
   (29–31 ms); Python costs ~5–11 ms more per fork because it forks a ~15 MB
   address space (the C supervisor measured its own `maxrss` at 1.8 MB). What
   language buys instead is a *one-off* start cost: 0 for shell, 25 ms for a Go
   binary, 124 ms for Python.
3. **A shell supervisor is not the enemy — a forking one is.** The best shell
   implementation beats the Python one. So the design rule is not "rewrite in
   Python"; it is "one process, and its bookkeeping must not fork".

### 19.4 The other half: overlap the forks

The same 20 execs from one supervisor, serial versus concurrent:

| concurrency | total |
| --- | --- |
| serial | 884 ms |
| 2 workers | 446 ms |
| 4 workers | 225 ms |
| 8 workers | **116 ms** |

Nearly perfect scaling, because each step is a sleeping process rather than CPU
work — which is exactly what this device has (8 slow cores, ~1 GB). It also says
the single-threaded batch is leaving **4–7× on the table for step-heavy plans**, and
that the declared capacity constants (`cpu 1`, `disk 1`, `net 2`) are the right
place to decide how wide a pass may go rather than a global thread count.

### 19.5 Does this generalize to less constrained machines?

**The shape generalizes; the urgency does not.** Wiring the same 20-step plan as
shell-with-five-forks costs ~50–100 ms on a laptop (forks 1–3 ms there) instead of
3.1 s. Nobody notices, and nothing breaks if the supervisor stays a shell script.

Break-even arithmetic, the same formula everywhere:

    a single-process supervisor wins when
    (bookkeeping forks per step × fork cost) > interpreter start

- **Here**: 5 × 40 ms = 200 ms/step against 124 ms of Python (25 ms of Go, or 0 for
  shell builtins) → it pays back on the *first* step.
- **A workstation**: 5 × 2 ms = 10 ms/step against ~25 ms of interpreter start →
  it pays back at ~3 steps. In practice: irrelevant either way.

What transfers unconditionally, because it is about correctness as much as speed:
batch the probes once per pass instead of per step; gate on declared constants
rather than measured state; treat the step as the leaf and the pass as the unit;
keep per-run stamps atomic; and let independent nodes run concurrently. None of
those cost anything on a fast host, and all of them are simpler to reason about
than per-step shell.

Where the reasoning gets *stronger* than on this phone, all with the same physics:

- **Windows**, where process creation is 10–50 ms even on fast hardware — the same
  order of magnitude as here, which is why a shell script with a few dozen
  `git` and `date` calls feels sluggish there too.
- **microVMs and syscall-sandboxed containers** (Firecracker, gVisor, Kata), where
  every fork crosses a boundary and costs far more than a native one.
- **1-vCPU CI runners and tiny cloud instances**, where a forked subprocess competes
  with the only core.
- **Hosts with a network filesystem or a slow disk under the home directory**, where
  each `stat` or `mkdir` in the bookkeeping is an RPC round trip rather than a
  syscall.

And where one long-lived supervisor is genuinely *worse*, which should be said
plainly: it becomes a crash domain (a bug in the bookkeeping kills the whole pass,
so per-step state must be atomic and resumable — §4's stance, not a new one); it
must reimplement shell semantics it used to get free (`trap`, subshell isolation,
`set -e`); it is harder to debug than `set -x` over a three-line step; and it adds a
dependency, since `sh` is universal and Python is not — which is precisely why §14
keeps the payload tier list, and why a Go supervisor (2 MB, 25 ms start) is the
portable way to have real-language bookkeeping on this host.

The synthesis, then: **leaves stay `sh -c`** (portability unchanged, zero
dependencies, 29–31 ms per fork, which is the floor anyway); **the supervisor is
one process per pass** — Python where it already exists (124 ms, amortised), Go
where start latency matters (25 ms) or the host has no Python; **the startup hook
stays builtins only**, because §18 shows that is already free and anything else
costs 100 ms.

### 19.6 Limits

- 20 steps in a loop, not a real DAG: no dependency resolution, no mixed payload
  sizes, no failure paths measured. The numbers scale linearly in forks, so the
  shape holds, but a 200-step plan with `git` payloads was not measured.
- Step cost varied 29–47 ms across sessions (§18.8), so per-step figures here are
  ±30 %; the 5× gap between implementations is far outside that noise.
- Concurrency was measured with `/system/bin/true`, i.e. sleepers, not CPU-bound
  payloads; 8 workers will not scale like that for real compilation.
- The Go and C supervisors were throwaway probes built to measure fork overhead,
  not proposals; nothing was added to the repo.

## 20. A real upkeep pass, priced end to end

§18 priced primitives and §19 priced the supervisor. This is the join: an actual
six-step upkeep pass, the same six commands, four implementations.

### 20.1 The plan

| step | command | deps |
| --- | --- | --- |
| git-status | `git -C ~/dotfiles status --porcelain` | — |
| disk-free | `df -Pk /data` | — |
| stamp-mtime | `stat -c %Y ~/.local/state/dotfiles/startups` | — |
| doc-gate | `node docs/spec-check.mjs` | git-status |
| snippet-count | `find profile.d -name "*.sh" \| wc -l` | — |
| py-probe | `python3 -c pass` | — |

One edge (the doc gate must not run while the tree is being read), five
independent nodes — the smallest plan that is still a DAG rather than a list.

### 20.2 Measured (min/median of 3 passes)

| implementation | pass time |
| --- | --- |
| shell, one `sh -c` per step, bookkeeping builtins, serial | 932 / 934 ms |
| shell, per-step forked bookkeeping (`date`+`mkdir`+`printf`+`stat`) + `sh -c`, serial | 976 / 1036 ms |
| supervisor, bookkeeping in-process, serial | **745 / 828 ms** |
| supervisor, bookkeeping in-process, 4 workers | **441 / 447 ms** |

### 20.3 Two checks that make the table trustworthy

- **The numbers add up.** Each step measured alone: 42 + 73 + 44 + 379 + 76 + 123
  = **737 ms**, against 745 ms for the serial supervisor pass. The supervisor adds
  ~8 ms of its own overhead for six steps; there is no hidden tax.
- **Concurrency hits the critical path.** The longest chain is
  `git-status` (42) → `doc-gate` (379) = 421 ms lower bound; measured 441 ms,
  i.e. 95 % of optimal. Four workers is enough because only five nodes are
  independent, so nothing here argues for a bigger fan-out.

### 20.4 What a pass costs, in one sentence each

- A **step** costs whatever its payload costs plus one fork (29–47 ms) — the
  payload *is* the budget, and a step cheaper than 40 ms is not worth splitting out.
- A **pass** costs the sum of its steps, minus the overlap the graph allows, plus
  ~1 ms per step of supervisor time. Overlap was worth 1.7× here (745 → 441).
- **Bookkeeping placement** is worth 25–45 % of the pass (976 → 745), and it is the
  only term the design controls without touching what the steps do.
- A **shell wrapper around each step** (`sh -c "..."`) costs an extra fork per
  step: 932 vs 745 ms, i.e. ~31 ms/step, and it buys nothing when the supervisor
  already has the argv.

### 20.5 Implications for the manifest

- Prefer **coarse steps**: one fork is 40 ms, so splitting a 100 ms step into two
  50 ms steps makes the pass slower, not more observable. Node granularity should
  follow payload boundaries (one tool invocation), not conceptual purity.
- Express the pass as a **graph with a declared fan-out**, not as a global thread
  pool; the declared capacity constants are already the right place for that
  (`cpu 1`, `disk 1`, `net 2` — §3).
- Keep the **one-edge rule honest**: the 421 ms critical path here is set by the
  slowest node, so a plan's wall time is governed by its longest dependency chain
  and only secondarily by how much work it contains.

### 20.6 Limits

- Six steps, one edge, three passes per variant: enough to validate the additive
  model, not enough to characterise a 40-node graph.
- The payloads are cheap and I/O-light; a pass containing a real `go build`
  or `rsync` would be dominated by throughput, not by any of this.
- Both shell variants pay an extra `sh -c` fork per step, which is normal for a
  step-runner but flatters nothing: the supervisor serial figure is the fair
  comparison, and it is the one used in the conclusions.

## 21. Shell entry flows: which of the four ways a shell starts here is expensive

The same dotfiles are entered by four different doors on this device. Only one of
them is slow, and §18 already says why.

### 21.1 Measured (min/median ms)

| flow | what uses it | time |
| --- | --- | --- |
| `sh -c exit` | Termux:Widget task floor, boot scripts | 19.6 / 44 |
| `bash -c exit` | `ssh host cmd`, `termux-job-scheduler` | 37.2 / 44 |
| `bash -l -c exit` | boot script, `su -c`-style login, ssh login then command | 37.7 / 72 |
| `bash -i -c exit` | a new interactive bash (tmux pane, `bash`) | **328 / 379** |
| `bash -l -i -c exit` | login + interactive | **326 / 329** |
| `zsh -i -c exit` | a new interactive zsh | **274 / 329** |
| `zsh -l -i -c exit` | login + interactive | **326 / 331** |
| `DOTFILES_SOURCED=1 bash -l -i -c exit` | the same shell with our snippets skipped | **39.5 / 42** |
| interactive shell nested in a non-interactive one | `bash -l -c "bash -l -i"`, editor terminals | 326 / 332 |
| `bash ~/.shortcuts/tasks/ip.sh` | the actual widget task | 237 / 325 |
| `bash ~/.shortcuts/tasks/sshd.sh` | the actual widget task | 226 / 275 |

Read the table as: **non-interactive paths are already at the floor** (37–44 ms,
i.e. the cost of starting bash at all), and **interactive paths are 274–379 ms**,
of which the guard-based test proves that ~100 % is our own snippet set:
`DOTFILES_SOURCED=1` collapses a login interactive bash from 326 ms to 39.5 ms.

Two corollaries that were not obvious before measuring:

- **Login costs nothing.** `bash -l -i` (326) ≈ `bash -i` (328), and `bash -l -c`
  (37.7) ≈ `bash -c` (37.2). Termux's `$PREFIX/etc/profile` gates on `PS1` and our
  guard gates on `DOTFILES_SOURCED`, and together they do their job: the second
  entry is free. Any "improvement" aimed at re-sourcing is aimed at a cost that
  does not exist.
- **Interactive shells nest additively.** 332 ms for an interactive shell inside a
  non-interactive one is just 37 + 295; there is no amplification, but it also
  means every extra pane pays the full tax (§18.6's history cost, in practice).

### 21.2 The daemon, measured rather than assumed

atuin 18.25 with `[daemon] enabled = true` against a cold socket:

| call | no daemon | daemon up |
| --- | --- | --- |
| `atuin history start -- true` | 119 / 127 ms | **73 / 74 ms** |
| `atuin history end -- 0 0` | 46 / 78 ms | 40 / 45 ms |

So the daemon removes ~40 % of the per-command tax but not the tax itself: the
remaining 73 ms is still a fork of a 20 MB binary per command. That is the honest
ranking — **the only fix for the per-command cost is not to fork per command**,
either by letting the supervisor own capture (§19) or by making it async. The
daemon is worth adopting anyway (it is ~46 ms/command for one 67 ms start per
boot), but it is not the fix.

### 21.3 Where a widget's 226–237 ms goes

Neither task is slow because of the shell (`sh` floor 20–44 ms); they are slow
because every line is a fork, and two of them are expensive:

| component | cost |
| --- | --- |
| `termux-toast` (one `am broadcast`) | 67 / 72 ms |
| `ip --json addr show dev wlan0 \| jq -r ...` | 72 / 75 ms (23 for `ip`, the rest is the pipe + `jq`) |
| `sv status sshd` | 23 / 40 ms |
| `pkill -0 -f sshd` | 45 / 76 ms |

`ip.sh` = shell + `ip` + `jq` + toast ≈ 200 ms, which is what was measured. The
three avoidable ones are `jq` (use `ip -4 -o addr show dev wlan0` and cut fields
in the shell), the second status probe, and the toast when the result is unchanged.
That is a task-script concern, not a profile concern — recorded here because the
widget is the one flow a user triggers by hand and notices.

### 21.4 Where the flows can be improved, ranked

Already measured in §18.6, unchanged by the flow data:

1. **Per-command history capture** — 106 ms/command; async or supervisor-owned.
   The daemon variant takes it to ~73 ms and is the cheap half of the fix.
2. **`"$cand" --version` probe in `70_history.zsh`** — 44 ms per shell start
   (269 → 225 ms). Replace with `[ -x ]` plus a one-time capability stamp.
3. **`compinit`** — 36 ms per shell (269 → 233) with a `-C` dump refreshed on
   the `df_due` schedule the manifest already has.

And the two things the flow table adds:

4. **Keep every machine path non-interactive.** Boot scripts, `termux-job-scheduler`
   payloads and widget tasks sit at 20–44 ms; the same work behind `bash -i` costs
   330 ms before it does anything. This is a rule for the task scripts, not an
   optimisation: nothing in this system may invoke an interactive shell.
5. **Do not target login or re-source cost.** Both are already ~0 (39.5 ms with
   the guard preset, 37.7 for `bash -l -c`); §18.5 measured the same for the
   `df_startup` write. Anything proposed there is unmeasured folklore.

### 21.5 Limits

- Terminal emulator start-up time is not in these numbers (it is Termux's, not
  ours), and the phone's thermal state moved `bash -i` between 270 and 380 ms
  across sessions — compare variants within one session only.
- `zsh -i` and `bash -i` were measured with the deployed `~/.zshrc`/`~/.bashrc`
  (both byte-identical to `src-dotfiles.sh`), not with a scratch tree, so these are
  end-to-end numbers including the `profile.d` loop.
- No `tmux` on this device, so "new pane" was proxied by nesting a shell inside
  `bash -l -c`; on a host with `tmux` the pane path adds a client start, not
  another profile load.
- `termux-toast`/`sv` costs move with Doze and with how many services run;
  single measurements of those are noise, which is why the medians are shown.


## Status

Draft. The verdicts are host facts as of 2026-11-25 plus the research's own
semantics; the minimal manifest in §6 is an illustration, not a decision. A
future record would need to choose: whether the allocator is imported here at
all, whether the two-state backend is the permanent shape, whether a
per-boot marker replaces the per-run marker on Termux, whether the shutdown
chain is formally replaced by crash-consistency plus quiesce, whether the SD
card is assumed (legacy storage) or probed (storage-class assert), whether
the staged-input convention is the whole answer to cross-app documents, whether
an isolation field with the three honest values in §12.6 is adopted or rejected,
and whether the foreign level is realised as generated single-workload apps, or as
one shim plus staged payloads (§14), built on the device or not at all, and
whether payloads are ever needed for an ABI other than arm64-v8a (§14.6), and
whether the conventional-build path of §15.6 is ever actually attempted, since
that is the only thing standing between "probably" and a measured answer, and
whether a full-system VM is ever used at all (§17), and whether `-sandbox on` is
even compiled in to the packaged `qemu-system`, the one claim in §17.2 left
unverified, and whether the file-backed-RAM approach of §17.3 is ever measured
under real guest pressure rather than the mmap proxy used here.
And, from §18: whether the three startup changes are adopted at all (the
`--version` probe removal, `compinit -C`, and an asynchronous or native
history capture), since they are three one-line edits worth 186 ms per shell and
~106 ms per command respectively, and whether the benchmark in §18 is ever
automated into the repo (it would need a scratch-DOTFILES harness; no script was
added), and whether any measurement here survives a second device or a reboot.
From §19: whether the supervisor is specified as one process per pass and in
which language (shell builtins: 0 ms start, Python: 124 ms, Go: 25 ms), and
whether passes run steps concurrently at all — the serial batch leaves 4–7×
unused on step-heavy plans — and whether the "no bookkeeping forks" rule becomes
a lint-able invariant rather than a note.
From §20: whether node granularity is specified at the payload boundary (one fork
per step, since a step cheaper than 40 ms should not be split), whether the pass
executor runs at the graph's declared fan-out instead of serially — the same six
steps are 745 ms serial and 441 ms at four workers — and whether the per-step
shell wrapper is dropped once the supervisor already holds argv (31 ms/step).
From §21: whether task scripts are kept permanently non-interactive by a lint rule
(an interactive shell in a machine path costs 300 ms before doing any work), and
whether the atuin daemon is started at boot as the cheap half of the history fix,
on the explicit understanding that it leaves a 73 ms per-command fork in place.
