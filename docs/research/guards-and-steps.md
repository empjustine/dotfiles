---
id: research-guards
type: architecture-design
status: draft
title: "Dotfiles — prior-art research: guards and steps"
parent: index
references: [index, design, decision-log, research-overview, research-upkeep-mapping]
---

# Dotfiles — prior-art research: guards and steps

This document collects the prior art for two related mechanisms: **guards**
that decide whether a unit of work should run at all, and **sequences** that
run several commands as one unit of work. Both are candidates for shrinking the
remaining one-off scripts in `config/upkeep/jobs.json`; neither is implemented
in the allocator today.

## systemd: conditions and asserts

Verified in `man/systemd.unit.xml` and `src/core/unit.c`, `src/core/job.c`.

- Conditions and asserts are evaluated **when the queued start job is about to
  execute**, after the units ordered before it have finished. Ordering and
  pull-in still happen as if the unit had started; the checks cannot
  conditionalise dependencies.
- All checks are ANDed. `Condition…=|…` makes a triggering OR: at least one
  triggering condition must pass, while all non-triggering conditions still
  have to pass. A leading `!` negates a typed check. An empty assignment resets
  the list.
- A failing condition is a quiet **skip**: the unit is not failed, its start job
  completes as done, and dependents still run. A failing assert is a **failed
  job** and is logged.
- The implementation makes the outcome explicit: condition unmet returns
  `-ECOMM` and the job finishes `JOB_DONE`; assert failure returns `-EPROTO`
  and the job finishes `JOB_ASSERT`. This is the vocabulary the allocator
  should copy: a condition-skipped job belongs in the `done` set, not in the
  failure set.
- The type set is the useful prior art: path existence, glob, directory,
  symlink, mount point, read-write, encrypted, socket, non-empty directory,
  non-empty file, executable; host name/machine ID/boot ID/product UUID;
  firmware, architecture, virtualization; environment, credential, security,
  capability, user, group; memory/CPU/IO pressure; needs-update and first-boot.
- There is **no container-runtime health condition**. `ConditionVirtualization`
  can say `podman` or `container`, but it describes the environment the manager
  runs in, not whether a named container is healthy.
- `ConditionHost` matches hostname (with shell-style globs), machine ID, boot ID
  or firmware product UUID. In a per-invocation manifest, the `hosts:` fan-out
  already performs the same job at load time, with validation and explicit
  per-host names.

The path family includes `ConditionPathIsMountPoint` and
`AssertPathIsMountPoint`; `AssertPathExists` and friends mirror the condition
set. That is a direct fit for the external-disk precondition.

## systemd: ExecCondition

Verified in `man/systemd.service.xml` and `src/core/service.c`.

- Runs before `ExecStartPre`, serially, regardless of `Type=`.
- Exit 0 continues; exit 1–254 **skips** the remaining commands and the unit is
  not failed; exit 255, a signal, or a timeout **fails** the unit.
- It is part of activation, not a unit-level condition: a skip transitions the
  unit from active to inactive and honours `SuccessAction=`, unlike
  `Condition…`/`Assert…`.
- There is no `unless` directive. The `!` executable prefix means elevated
  privileges, not negation; you invert inside the command.
- The manual warns against long-running work and recommends the same care as
  `ExecStartPre`.

This is the right shape if an exec predicate is ever added: one boolean check
with a three-way result, not two directives with duplicated polarity.

## Other guard prior art

| system | mechanism | semantics |
| --- | --- | --- |
| Docker Compose | `depends_on: condition:` | `service_started`, `service_healthy`, `service_completed_successfully`; Compose also has a `running_or_healthy` condition for wait-style checks; typed and named, used for ordering/waiting, not skip |
| Pitchfork | `ready_http`, `ready_port`, `ready_output`, `ready_cmd`, `ready_delay`, `oneshot` | typed readiness checks; first successful check wins; used to wait, not to skip work |
| mise | `skip_if` | shell command; exit 0 skips the task, prints a reason, counts the task as successful and as having done no work; a probe that cannot start, times out, or is signalled fails the task; `--force` bypasses; `--dry-run` prints |
| mise | `sources`/`outputs` | mtime freshness; a task with sources but no outputs uses a marker file; a failed run records nothing, so the task stays stale |
| Kubernetes | `livenessProbe`/`readinessProbe` | `exec` or `httpGet` probes with thresholds; used for health and readiness, not skip |
| systemd | `Condition…` vs `Assert…` | condition = skip with success; assert = hard failure; both evaluated at job execution time |

The mise `skip_if` documentation is the closest match to the proposed
`ConditionExecIf`/`Unless` pair, and it spells out the design consequences:
skip must be a success, must not count as work, must not hold locks, and a
broken probe must **fail** rather than silently skip. The note that a task
which must fail instead of skip should put the check in `run` and `exit 1` is
the condition/assert distinction in one sentence.

## Command sequences

| system | shape | semantics |
| --- | --- | --- |
| systemd `Type=oneshot` | repeated `ExecStart=` | serial, in order; a non-zero command stops the rest unless prefixed `-`; one `TimeoutStartSec` for the whole activation; `RuntimeMaxSec` has no effect; a clean exit is never restarted |
| systemd `ExecStartPre=`/`ExecStartPost=` | repeated directives | same serial/abort/`-` rules, regardless of `Type=`; `ExecStartPre` must not start long-running processes |
| mise | `run = string \| (string \| {task} \| {tasks})[]` | serial, stops at the first failure; entries may invoke tasks with their own dependencies; `{tasks: [...]}` runs in parallel |
| process-compose | `command` string + `depends_on` | commands are shell strings, not argv; five dependency conditions; readiness/liveness probes; `availability` restart/backoff |
| Kubernetes | `initContainers` | serial, each must complete successfully; a failure follows the pod restart policy |
| Podman kube play | `initContainers` | init type `once` by default; an annotation can make it `always`; no real Job controller |
| Dockerfile | `RUN` | build-time layers, not runtime sequencing |

The two closest models are systemd and mise. systemd's choices are worth
copying because they have survived a long time: one command list, serial
execution, abort on failure, an explicit per-command ignore-failure form, one
timeout for the whole list, and a single executor (one unit). mise adds the
useful idea that a step may invoke another task, but that is out of scope while
upkeep keeps its own DAG.

## What this implies for upkeep

### Conditions and asserts

- Model three outcomes internally: run, skip-with-success, fail. Today the
  allocator has `done`, `failed`, and a `skipped` set that marks descendants of
  failures; a condition skip must join `done` and get a separate counter.
- A condition-skipped job must release its tokens, consume no retry, not
  trigger `skip_descendants`, and not deadlock the stuck detector.
- Evaluate after all `after` dependencies are `done` and the resource claim is
  held, immediately before `start()`. Give each check a short deadline and do
  not retry it. systemd's own warning about long-running `ExecCondition` applies
  to slow SSH and Podman probes.
- Evaluate asserts before conditions, unlike systemd's order, so a missing
  external disk is reported even for a job whose condition would have skipped
  it. Document the deviation if it is taken.
- Keep the typed set small: path existence/directory/mount-point/file-not-empty/
  file-executable, environment-variable-present, command-exists, and a small
  container family. Do not add a general shell predicate.
- If an exec predicate is added later, use one `exec` boolean with 0 = true,
  1–254 = false, ≥255/signal/timeout = error, plus `not` composition. This
  subsumes both proposed directives and preserves the "broken probe fails"
  property.

### Steps

- `steps` (or `argv: string[][]`) should mean: serial, stop on first failure,
  one job-level timeout, one retry policy, one token set held throughout, one
  executor (one systemd unit, one tmux pane, one SSH connection, or one console
  process).
- Add a per-step ignore-failure form only if idempotent flags cannot replace
  the guard. `podman rmi --ignore`, `podman manifest create --amend`,
  `podman volume create --ignore`, `podman rm --ignore` and `systemctl start`
  remove most of the need.
- Local jobs can use a small step runner as the unit's `ExecStart`; remote jobs
  should keep the single `script` transport until a remote step runner can
  preserve the one-SSH property. Do not open one SSH connection per step.
- The step runner must forward signals to the child process group, stop on the
  first non-zero status, and propagate that status. It must not introduce a
  shell or a shell string.
- `plan` should print numbered steps; logs should prefix `step N/M`.

## Local audit

`config/upkeep/jobs.json` has nine `script` jobs (
`podman-build`, `syncthing`, `ssh-upkeep`, `act-logs`, and five Oracle steps).
Their conditionals classify as follows:

| script | internal step guards | job-level assert | job-level skip | "only if wrong" |
| --- | ---: | ---: | ---: | ---: |
| `upkeep-local/podman-build.sh` | 2 | 0 | 0 | 0 |
| `upkeep-remote/oracle-services.sh` | 0 | 0 | 0 | 0 |
| `upkeep-remote/oracle-swap.sh` | 0 | 0 | 0 | 1 |
| `upkeep-remote/oracle-network.sh` | 0 | 0 | 0 | 0 |
| `upkeep-remote/oracle-containers.sh` | 0 | 0 | 0 | 0 |
| `-start-syncthing.sh` | 3 | 1 | 0 | 0 |
| `-start-transmission.sh` | 3 | 1 | 1 | 0 |
| `-upkeep-act-logs.sh` | 0 | 2 | 0 | 0 |
| `-ssh-upkeep.sh` | 2 | 0 | 0 | 0 |
| **total** | **10** | **4** | **1** | **1** |

Ten of the sixteen conditionals are internal resets or fallback choices
between verbs. Six are non-idempotent workarounds (image exists → remove,
container exists → stop/remove, volume exists → remove) and two are path
fallbacks; the rest are genuine asserts or one genuine state comparison. A
job-level guard language can only address the 6 job-level cases, and
idempotent verbs address most of those. This is the quantitative reason a
generic exec guard is not the next lever.

## Open questions

- Does the allocator evaluate asserts before conditions, or follow systemd and
  evaluate conditions first? The recommendation above is asserts first.
- Is a step allowed to be a task reference (`{task: ...}`, as mise allows), or
  only an argv list? Task references need a nested scheduler and are out of
  scope for the first version.
- Do remote jobs get steps, or stay single-script until a remote step runner
  exists? The one-SSH invariant argues for staying single-script.
- If an exec predicate is added, does a timeout count as a failed job even under
  a negated condition? systemd says yes; a negated timeout must not turn into a
  skip.
- Should a skipped condition be written to the journal with the same prominence
  as an assert, or only at debug level? maintainers need to see "why did this
  not run" without reading every run.
