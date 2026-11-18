---
id: execution-map
type: architecture-design
status: active
title: "Dotfiles — expected execution map"
parent: index
references: [goal, system, design, decision-log]
---
# Dotfiles — Expected Execution Map

This document states *what is expected to run, where, in what order, at what
cost* — the third axis next to [requirements.md](requirements.md) (what must
be achieved), [system.md](system.md) (how it works) and [design.md](design.md)
(why it is built this way). It exists to answer, for any host, distro family
or invocation shape: **which files get sourced, which of them do anything, and
what do they cost?**

Status of every claim below: verified on 2026-11-18 with bash 5.x (Fedora
host) and zsh 5.9 (Debian 13 container), with `./lint.sh` passing (shfmt
3.14.1 + shellcheck + `zsh -n`). Rows marked *(measured)* were observed;
the rest are derived from the code and the distro documentation.

## 1. Two layers

```
layer 1  upstream    /etc/profile, /etc/profile.d/*.sh, /etc/bashrc,
                     /etc/bash.bashrc, $PREFIX/etc/profile, cloud rc,
                     /etc/zshenv, /etc/zprofile, /etc/zshrc
                     -> exists whether or not we do; the distro/provider owns it

layer 2  dotfiles    ~/.bash_profile | ~/.bashrc | ~/.zprofile | ~/.zshrc
                     = byte-identical copy of src-dotfiles.sh
                     -> DOTFILES_SOURCED guard
                     -> lib/dotfiles.sh (run-guard helpers, DR-043)
                     -> profile.d/* in glob order
```

The two layers interact in exactly one place: `profile.d/20_core.bash`
re-sources the upstream files that our entrypoint displaced (because our
`~/.bashrc` *is* the entrypoint, the distro never gets to run its own
`~/.bashrc` → `/etc/bashrc` chain). `80_path.sh` uses the same cloud/Termux
markers to decide whether PATH may be reset.

## 2. Upstream layer per distro family

| family | bash login | bash non-login interactive | zsh login | zsh non-login interactive | re-sourced by `20_core.bash` |
|---|---|---|---|---|---|
| Fedora / RHEL / Silverblue / WSL2-Fedora | `/etc/profile` → `/etc/profile.d/*.sh`, then `~/.bash_profile` | `~/.bashrc` only | `/etc/zshenv` → `~/.zshenv` → `/etc/zprofile` (which sources `/etc/profile`) → `~/.zprofile` | `/etc/zshrc` → `~/.zshrc` | `/etc/bashrc` |
| Debian / Ubuntu | `/etc/profile` → `/etc/profile.d/*.sh` (run by the login shell — `dash` for POSIX `sh` logins), then `~/.bash_profile` | `~/.bashrc` | `/etc/zsh/zshenv` → `~/.zshenv` → `/etc/zsh/zprofile` (**does not** source `/etc/profile`) → `~/.zprofile` | `/etc/zsh/zshrc` → `~/.zshrc` | `/etc/bash.bashrc` |
| Termux (Android) | `$PREFIX/etc/profile` → `~/.bashrc` (interactive, non-posix), then `~/.bash_profile` | `$PREFIX/etc/profile` → `~/.bashrc` | same shell files as Android bash where zsh is installed | same | `$PREFIX/etc/profile` |
| Google Cloud Shell | provider chain, then `~/.bash_profile` | provider chain, then `~/.bashrc` | same + zsh optional | same | `/google/devshell/bashrc.google` |
| Oracle OCI Cloud Shell | provider chain, then `~/.bash_profile` | provider chain, then `~/.bashrc` | n/a | n/a | `/etc/bashrc.cloudshell` |

Consequences that are easy to get wrong:

- **Upstream runs first or not at all.** On bash the entrypoint is reached
  *after* `/etc/profile` (login) but *instead of* the distro `~/.bashrc`
  (non-login) — hence the explicit re-source in `20_core.bash`.
- **`/etc/profile.d/*.sh` may run under `dash`** for POSIX `sh` logins on
  Debian — the reason every `*.sh` snippet in `profile.d/` must stay
  dash-clean (DR-002), even though our own entrypoint is normally read by
  bash or zsh.
- **Debian's zsh login chain never sources `/etc/profile`** → a pure
  `/etc/profile.d` deployment covers bash login everywhere but zsh login only
  on Fedora, and never non-login interactive shells. Per-user entrypoints
  stay mandatory.
- **`~/.zshenv` is deliberately not deployed.** Every `zsh` invocation
  (`zsh -c …`, scripts with a `#!/usr/bin/zsh` shebang) reads `~/.zshenv`;
  only login/interactive zsh reads `~/.zprofile`/`~/.zshrc`. Not deploying
  `~/.zshenv` is what keeps the dotfiles out of `zsh -c` — see §3.

## 3. Evaluation shapes (environment / variant matrix)

`I` = interactive, `L` = login. The dotfiles chain runs in shapes 1–4 and in
no other; that is a property of *which rc file the shell reads*, not of any
guard we write.

| # | shape | examples | rc file read | dotfiles chain runs? | expected effect |
|---|---|---|---|---|---|
| 1 | bash **IL** | tty login, `ssh host`, `sudo -i`, `su -`, tmux new session | `/etc/profile` → `~/.bash_profile` | **yes** (once) | everything enabled: env, PATH, completions, atuin, keybinds |
| 2 | bash **I**, non-login | nested `bash`, new tmux pane/window, IDE terminal, `ssh -t host bash` | `~/.bashrc` | **yes** (once) | same as 1 except upstream `/etc/profile` (re-sourced only via `20_core.bash` → `/etc/bashrc`) |
| 3 | zsh **I** (login or not) | `zsh`, tmux pane running zsh, `ssh -t host zsh` | `~/.zprofile` (L) / `~/.zshrc` | **yes** (once) | same, zsh flavour (compinit, bindkey) |
| 4 | Termux **I** | Termux session, Termux:Widget task | `$PREFIX/etc/profile` → `~/.bashrc` | **yes** (once, guard stops the double read) | as 1/2, PATH untouched, no `ip.json` write |
| 5 | bash **non-I, L** | `ssh host cmd`, `bash -lc cmd` from CI | `~/.bash_profile` | **yes** | env + PATH only; no completions/hooks; WSL2 privileged block skipped |
| 6 | bash **non-I, non-L** | `bash -c cmd`, git hooks, cron, systemd-run, Makefile recipe, `scp`/`rsync`/`sftp` remote side | *(none)* | **no** — `bash -c` reads no rc file (unless `BASH_ENV`) | nothing; a caller that wants the env must use `bash -lc` |
| 7 | zsh **non-I** | `zsh -c cmd`, `#!/usr/bin/zsh` scripts | `~/.zshenv` only | **no** (not deployed) | nothing |
| 8 | any shell, wrong entrypoint | manual `source ~/dotfiles/profile.d/70_history.bash` under zsh | — | n/a | per-file shell guard + stderr warning (DR-018) is the only protection |

Shape 5 vs 6 is the one that surprises people: a login bash in a
non-interactive context (`ssh host cmd`) **does** run the chain (env, PATH,
`70_moratorium.sh`) but must not install completions or hooks — that is
exactly what the `case "$-" in *i*)` gates protect (DR-017).

### Host variants layered on top of a shape

| variant | detection | what it changes |
|---|---|---|
| WSL2 Fedora | `$WSL_DISTRO_NAME` non-empty | `XDG_RUNTIME_DIR` slash strip (always); one per-boot privileged block (tmpfs ownership, `fstrim /`, shared-root propagation, `/mnt/wsl/<distro>` bind) + keyring — interactive only |
| Fedora Silverblue / Bazzite | none (default branch) | wholesale PATH reset; no zsh by default → entrypoints absent until installed |
| Debian / Ubuntu | none (default branch) | `/etc/bash.bashrc` re-source instead of `/etc/bashrc` |
| Termux | `-d /data/data/com.termux/files/usr` | PATH never reset; atuin Termux slot reachable; no `ip.json` write from startup |
| Google Cloud Shell | `-r /google/devshell/bashrc.google` | provider rc sourced; PATH never reset |
| Oracle OCI Cloud Shell | `-r /etc/bashrc.cloudshell` | provider rc sourced; PATH never reset |
| native Windows (Git Bash, MSYS2, Cygwin, PowerShell) | — | **out of scope** (DR-038): no `.exe`/scoop/PS code paths exist any more; use WSL2 |

## 4. Per-snippet evaluation map

`always` = every shape the chain runs in; `I` = interactive only; `bash`/`zsh`
= that shell only. Forks are external processes spawned per matching shell.

| snippet | gate | forks per shell | world side effects | throttle |
|---|---|---|---|---|
| `10_wsl2.sh` | `$WSL_DISTRO_NAME`, then `I` for everything privileged | 0 (non-WSL / non-I); up to 4 `sudo` + 2 `findmnt` | strip `XDG_RUNTIME_DIR` slash; per boot: tmpfs ownership, fstrim, mounts; keyring start | per-boot stamp `.dotfiles-wsl-<boot_id>-<uid>`; keyring by `GNOME_KEYRING_CONTROL` |
| `20_core.bash` | `bash` | 0 | re-sources upstream rc | none (must run every shell) |
| `40_completion.bash/.zsh` | `bash`/`zsh`, then `I` | 0 warm (`mise activate` is a hook: 1 generator + eval, ~29 ms); **4 on a refresh** (`mise`, `uv`, `uvx`, `kubectl`) | writes the completion cache (`$XDG_CACHE_HOME/dotfiles/completions/` or `$XDG_DATA_HOME/zsh/site-functions/`) | `df_due completions` — every `DOTFILES_RUN_EVERY` (50) startups or `DOTFILES_RUN_AGE` (86400 s), plus a forced refresh when a tool binary is newer than its blob (DR-041, DR-043) |
| `60_containers.sh` | always | 1 (`find`) + 1 (`tr`), only when `~/.kube/config.d` exists | none (sets `KUBECONFIG`) | none (cheap) |
| `70_history.bash/.zsh` | `bash`/`zsh`, then `I` | 1 (`atuin --version` per candidate until one validates, then `atuin init`) | none | none — hooks are in-shell state |
| `70_history.sh` | always | 0 in steady state (2 in-shell `-d` tests; `mkdir` only when a dir is missing) | creates `$XDG_STATE_HOME`, `$XDG_CONFIG_HOME/vim`; folds legacy history files | pre-check, self-healing (no stamp) |
| `70_moratorium.sh` | always | 0 | none (env vars only) | n/a |
| `80_path.sh` | always | 0 | replaces `PATH` (except cloud/Termux); exports `ANDROID_HOME` | n/a |
| `90_navigation.zsh` | `zsh`, `I`, `TERM=xterm-256color` | 0 | none (keybinds) | n/a |
| `lib/dotfiles.sh` | sourced by the entrypoint, before the loop | 0 | one counter write in `$XDG_STATE_HOME/dotfiles/startups` when `df_startup` is called (interactive consumers only) | n/a — it *is* the guard (DR-043) |
| `shortcuts/tasks/*.sh` | Termux:Widget task (never startup) | — | restart sshd / write `ip.json` | n/a — user-initiated |

Nothing in the startup chain writes to world state on every shell any more:
the only such writes are the WSL2 privileged block (once per boot), the REPL
dir creation (only when missing), the REPL history fold (only when a legacy
file exists), the completion cache (only when the run-guard says so) — and the
single counter file the guard itself needs to answer "every N" (DR-043).

## 5. Expected costs *(measured 2026-11-18)*

| scenario | wall time |
|---|---|
| `bash -ic true` (bare, no dotfiles) | 3 ms |
| interactive bash + full chain, **before DR-041** | 106–114 ms |
| interactive bash + chain, `DOTFILES_SOURCED=1` (guard trips) | 5 ms |
| `zsh -ic true` (bare) | 8 ms |
| interactive zsh + full chain, **before DR-041** | **196 ms** |
| zsh: `compinit` alone | 25 ms |
| zsh: `eval "$(uv generate-shell-completion zsh)"` | 103 ms (≈85 ms of it is the eval, not the spawn) |
| **after DR-041** — interactive bash, warm / refresh | **51 ms** / 108 ms |
| **after DR-041** — interactive zsh, warm / refresh | **83 ms** / 148 ms |
| lazy registration (3 `complete` builtins) | 0 ms |
| first TAB load: uv / kubectl | 22 ms / 4 ms |
| zsh: the same completions via `$fpath` + lazy `compinit` autoload | 25 ms total (= bare `compinit`) |
| zsh: `eval "$(mise activate zsh)"` | 34 ms |
| the five `.sh` snippets under zsh (`emulate -L ksh` each) | 9 ms |
| `mise activate bash` spawn / eval | 9.6 / 18 ms |
| `uv generate-shell-completion bash` spawn / eval (483 KB blob) | 20 / 11 ms |
| `uvx --generate-shell-completion bash` spawn / eval | 12 / 2 ms |
| `sudo -n true` (per call, WSL2 block) | 9 ms |
| `findmnt` (per call, WSL2 block) | 2 ms |
| `mkdir -p` (per call, old `70_history.sh`) | ~1 ms |
| WSL2 interactive login, before → after DR-038 | −22 ms (4 `sudo`/`findmnt` forks → 1 `-e` test) |

So ~85 ms of a ~110 ms bash startup — and ~160 ms of a ~196 ms **zsh** startup —
is the generated completion blobs. They must never be throttled away: they
install in-shell state, so a skipped refresh means a shell without
completions. What *may* be throttled is writing them to disk or to `$fpath`.

### 5.1 Lazy completions, both shells (applied — DR-041, DR-043)

Completions were ~75 % of a bash startup and ~85 % of a zsh one: the
generators fork a process and their output is large (uv alone is 569 KB for
zsh, 483 KB for bash). Both shells now load a completion only when one is
requested.

| tool | zsh artifact | bash artifact | size (zsh / bash) |
|---|---|---|---|
| `uv` | `#compdef uv` → `_uv` | `complete … -F _uv uv` | 569 KB / 483 KB |
| `uvx` | `#compdef uvx` → `_uvx` | same family | 19 KB / 17 KB |
| `kubectl` | `#compdef kubectl` → `_kubectl` | plain `complete` script | 8 KB / 17 KB |

**zsh — `$fpath` autoload.** The `#compdef` files are written into
`$XDG_DATA_HOME/zsh/site-functions/`, which is first in `$fpath`; `compinit`
registers them and the bodies load on the first TAB. Verified: `functions[_uv]`
is the unloaded `autoload -XU` stub and `_comps[uv]=_uv` / `_comps[uvx]=_uvx`.

**bash — one shared self-replacing stub.**

```bash
complete -o bashdefault -o default -o nosort -F _df_lazy_comp uv uvx kubectl
```

`_df_lazy_comp` sources the cached blob (which replaces its own registration
with the real completer), reads that registration back out of `complete -p` and
dispatches to it, so the TAB that paid for the load still completes. Verified:
`complete -p uv` flips from `-F _df_lazy_comp` to the blob's own `-F _uv`.

**Refresh — the world-state half — is behind the run-guard** (DR-043): every
`DOTFILES_RUN_EVERY` startups (50) or `DOTFILES_RUN_AGE` seconds (86400),
whichever comes first, and forcibly when a tool binary is newer than its blob.
A skipped refresh costs two `-e`/`-nt` builtins per tool.

| shell | before | after, warm | after, on a refresh |
|---|---|---|---|
| bash interactive | 106–114 ms | **51 ms** | 108 ms |
| zsh interactive | 196 ms | **83 ms** | 148 ms (first ever run: ~0.95 s — compdump) |

**What stays eager:** `mise activate <shell>` (29 ms bash / 34 ms zsh — a
PROMPT_COMMAND/chpwd hook, not a completion), the bash-completion framework
(5 ms), `compinit` (25 ms) and `brew shellenv` (PATH; belongs in `80_path.sh`
per the deferred (c) item). Deferring those changes behaviour, not just speed.
## 6. Order and the guard

1. upstream (`§2`)
2. entrypoint: `DOTFILES_SOURCED` check → `DOTFILES_SOURCED=1` → source
   `lib/dotfiles.sh` (if present; every caller guards on the helper existing)
   → glob `profile.d/*` in lexicographic order (numeric prefixes enforce
   `10 → 90`)
3. inside the loop: shell filter by extension (`.sh` all, `.bash` bash,
   `.zsh` zsh) — a `.sh` under zsh is sourced inside `emulate -L ksh`
4. each snippet applies its own interactivity / platform gate as its first
   statement; throttled work asks the run-guard (`df_startup` + `df_due`)
   before doing anything expensive (DR-041, DR-043)
5. the guard makes any second entry in the same process a no-op — Termux
   login (`$PREFIX/etc/profile` → `~/.bashrc` **and** `~/.bash_profile`) and
   `20_core.bash`'s profile re-source are therefore exactly one run

Expected totals per shape: shape 1 → 1 run, shape 2 → 1 run, shapes 1+2 in
one process (Termux login) → 1 run, shapes 5 → 1 run with the interactive
gates closed, shapes 6–7 → 0 runs.

## 7. How to verify on a host

```sh
# which files are sourced, in which order
bash -lic 'set -x; . ~/dotfiles/src-dotfiles.sh' 2>&1 | grep -o "profile.d/[0-9a-z_]*\." | uniq

# startup cost, cold vs guarded
TIMEFORMAT='%3R'; time bash -lic '. ~/dotfiles/src-dotfiles.sh'
TIMEFORMAT='%3R'; time bash -lic 'DOTFILES_SOURCED=1'

# shape checks
bash -lc  'echo non-interactive-login: -*-=$-'   # expect: hBc (no i)
bash -ic  'echo interactive:            -*-=$-'   # expect: contains i
bash -c   'echo non-interactive:        -*-=$-'   # expect: no rc read at all

# guard behaviour: second source must be a no-op
bash -lic 'DOTFILES=~/dotfiles; . $DOTFILES/src-dotfiles.sh; . $DOTFILES/src-dotfiles.sh'

# no scratch leakage
bash -lic '. ~/dotfiles/src-dotfiles.sh; declare -F | grep -E "_dotfiles_|merge_history" || echo clean'
```

## 8. Proposal (not applied — DR-039): hoisting the gates into the entrypoint

Today every snippet carries its own one-line guards (7 × `case "$-" in *i*)`
and 3 shell-exclusivity blocks + stderr warnings). The proposal: let
`src-dotfiles.sh` be the single gatekeeper, and encode the gate in the
**file name**, so a snippet body starts with its content, not with
boilerplate.

| option | mechanism | buys | costs |
|---|---|---|---|
| **A. Suffix convention** | `NN_name.int.sh` / `.int.bash`; entrypoint sources `*.int.*` only when `$-` has `i` | zero boilerplate; one uniform gate; grep-able (`ls *.int.*` = the interactive set); no new tooling | the second defence layer of DR-018 disappears — a *manually* sourced file runs ungated; the wrong-shell warning must move into the entrypoint (which cannot know the caller's intent); `.int.bash` still needs shell filtering |
| **B. Directory split** | `profile.d/always/*`, `profile.d/interactive/*` | very explicit | two globs must be merged *and* ordered together (the numeric prefixes are the whole ordering scheme, DR-001); 10..90 ordering across directories is fiddly; more churn |
| **C. Header manifest** | first line `# gates: interactive bash` parsed by the entrypoint | gate data next to the code, extensible (e.g. `# gates: wsl2`) | a `read`/`case` per snippet per shell (cheap but nonzero), plus a parser to maintain; still per-file boilerplate, just different |

Assessment: A is the only variant that is strictly shorter and strictly
more symmetric, and its real cost is philosophical — DR-018 bought
defence-in-depth by duplicating the gate; A removes that duplication.
Recommended shape if it is ever applied: keep the *shell* filter in the
entrypoint (it already exists), move the *interactivity* filter there as a
filename suffix, and keep a single `df_wrong_shell`-style helper for the
manual-sourcing case. Prerequisite: a decision record amending DR-017/DR-018
and NFR-4, plus `lint.sh`/`shfmt` awareness of the new suffix (shfmt keys on
extension; `*.int.sh` still ends in `.sh`, so it is covered). Nothing here
is applied yet.

## 9. Rejected: merging the bash and zsh snippets (DR-040)

`40_completion.{bash,zsh}` and `70_history.{bash,zsh}` are now byte-identical
except for (a) the framework block (`bash_completion.sh` vs `compinit`) and
(b) the shell word passed to the generated blob — which makes a merge into one
`.sh` file look mechanical. It is not, and the reason is structural: **under
zsh every `.sh` snippet is sourced inside `emulate -L ksh`** (DR-003), so moving
shell-generated code into a `.sh` file changes the semantics it executes under.

Measured (zsh 5.9):

```sh
# plain zsh — clean
zsh -ic 'autoload -U compinit; compinit -u; eval "$(uv generate-shell-completion zsh)"; print ${_comps[uv]}'
#   -> _uv

# same code inside emulate -L ksh, i.e. what a .sh snippet would do
zsh -ic 'autoload -U compinit; compinit -u; f() { emulate -L ksh; eval "$(uv generate-shell-completion zsh)"; }; f'
#   -> f: bad output format specification   (once per completion function, hundreds of lines)
```

Cause: the generated zsh completion guards its definitions with
`(( $+functions[_uv_commands] ))`. Under ksh emulation `KSH_ARRAYS` is active,
so `$+functions[x]` is parsed as `${+functions}` followed by a **literal**
`[x]`, i.e. `(( 1[x] ))` — an arithmetic error per function. The completion
still *registers* at the end (`compdef _uv uv`), so the damage is silent at a
glance and surfaces later as broken tab completion. The same class of breakage
applies to `atuin init zsh` (zle widgets, hooks, array handling) and
`mise activate zsh`.

Second, independent reason: the two history paths are not equivalent today.
Bash has no native `preexec`, so atuin's bash integration installs
`PROMPT_COMMAND`/preexec machinery, while zsh has native `precmd`/`preexec`.
The bash path is currently the *degraded* one (§10). Merging bodies would put
a working path and a broken one in the same file and remove the ability to fix
or tune them independently.

Verdict: `.sh` stays POSIX-only logic; `.bash`/`.zsh` keep shell-generated
wiring. The only shareable part is the pure discovery cascade (POSIX function),
which belongs to the deferred helper-lib decision (b/c) — not to a merge.

## 10. Open functional issue: atuin history loss under bash

Reported on the real host: bash loses history entries at random even after the
vendored bash-preexec was removed (DR-037) and atuin ≥ 18.18 supplies its own
backend. Recorded here because it blocks every "simplify the history path"
idea, and because our invocation can hide the failure:

```sh
eval "$("$atuin_bin" init bash --disable-up-arrow || true)"   # 70_history.bash
```

`|| true` turns a failing `atuin init` into an empty `eval` — i.e. **no hooks at
all, silently, per shell**. Diagnostics to run in an affected session and in a
clean one for comparison:

```sh
atuin --version; atuin doctor 2>/dev/null | head -20
declare -p PROMPT_COMMAND                  # string or array? whose hooks are in it?
declare -F __atuin_precmd __atuin_preexec  # hooks actually installed?
echo "preexec_imported=${bash_preexec_imported:-} bp=${__bp_imported:-} ble=${BLE_ATTACHED:-}"
trap -p DEBUG                              # nothing should own DEBUG
# does a bare shell record, with the same binary and the same terminal?
env -i HOME="$HOME" TERM="$TERM" bash --norc -i
```

Suspects, none verified yet: (1) `|| true` swallowing an init failure;
(2) `mise activate bash` (`40_completion.bash`) installing its `PROMPT_COMMAND`
hook *before* atuin (`70_history.bash`) and a later rewrite dropping atuin's;
(3) `PROMPT_COMMAND` being turned into an array by something in the chain, which
atuin's bash hook may not expect; (4) a second `atuin init` in the same process
(the `DOTFILES_SOURCED` guard should prevent it, but a manual re-source or an
extra interactive layer would defeat it). First cheap hardening, if it is
pursued: report a failed `atuin init` on stderr instead of swallowing it.
