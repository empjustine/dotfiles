# Dotfiles — Systems Reference (SRD)

This document describes *how the system works*: components, startup chains,
runtime behavior per environment, and side effects. *What it must achieve and
where* is in [requirements.md](requirements.md) (BRD); *why it is built this
way* is in [design.md](design.md) (TDD) and [../DECISIONS.md](../DECISIONS.md).
Known documentation inconsistencies are tracked in
[known-issues.md](known-issues.md).

## 1. System overview

```
$PROFILE / ~/.bash_profile / ~/.bashrc / ~/.zprofile / ~/.zshrc
        │  (each is a copy of src-dotfiles.sh — or src-dotfiles.ps1)
        ▼
src-dotfiles.sh ── DOTFILES_SOURCED re-entrancy guard (DR-027)
        │
        ▼  loop over ${DOTFILES:-$HOME/dotfiles}/profile.d/* in glob order
           *.sh   POSIX, every shell (zsh: wrapped in `emulate -L ksh`)
           *.bash bash-only    (guarded on $BASH_VERSION)
           *.zsh  zsh-only     (guarded on $ZSH_VERSION)
```

## 2. Component inventory

| file | role |
|---|---|
| `src-dotfiles.sh` | unified POSIX entrypoint; guard + `profile.d/` loop. Copied verbatim to the rc targets by `deploy.sh` |
| `src-dotfiles.ps1` | PowerShell analog of the entrypoint (5.1 & 7.x); sources only `*.ps1` snippets (DR-030) |
| `profile.d/10_wsl2.sh` | WSL2 plumbing: `XDG_RUNTIME_DIR` normalization, throttled `fstrim /`, shared-root propagation, cross-distro bind mount, gnome-keyring (DR-007) |
| `profile.d/20_core.bash` | sources the distro/cloud/system bashrc (`/etc/bashrc`, `/etc/bash.bashrc`, Termux profile, Google/Oracle cloud bashrc) (DR-020, DR-022.3) |
| `profile.d/40_completion.{bash,zsh,ps1}` | tab completion: bash-completion framework, brew shellenv, mise activate, uv/uvx, kubectl (DR-021, DR-031) |
| `profile.d/50_ip.sh` | writes `ip --json addr` to the Markor Documents folder (Termux only, interactive-only; DR-009) |
| `profile.d/60_containers.{sh,ps1}` | dynamic `KUBECONFIG` from `~/.kube/config.d` (`;` on Win32, `:` elsewhere; DR-032) |
| `profile.d/70_history.{bash,zsh,sh,ps1}` | atuin hooks (allowlisted discovery, DR-016); REPL history relocation + legacy merge (`70_history.sh`) |
| `profile.d/70_moratorium.sh` | supply-chain env vars: release-age windows, `NPM_CONFIG_IGNORE_SCRIPTS`, `PIP_REQUIRE_VIRTUALENV` (DR-005, DR-006, DR-011) |
| `profile.d/80_path.sh` | PATH policy: wholesale POSIX reset (DR-014) vs append-only Win32 (DR-022.2, DR-029); `ANDROID_HOME` |
| `profile.d/90_navigation.zsh` | xterm-256color keybindings (word-jump, Home/End/Delete) |
| `shortcuts/tasks/sshd.sh` | Termux:Widget background task — restart sshd and toast its status (was embedded in `termux-shortcuts.html`); copied verbatim to `~/.shortcuts/tasks/sshd.sh` by `deploy.sh` (DR-036) |
| `shortcuts/tasks/ip.sh` | Termux:Widget background task — refresh `ip.json` for Markor and toast the primary IPv4 (DR-009, DR-036); copied to `~/.shortcuts/tasks/ip.sh` by `deploy.sh` |
| `deploy.sh` | copies `src-dotfiles.sh` onto the rc targets (zsh targets only when zsh exists); Termux:Widget dir scaffolding + `shortcuts/tasks/*.sh` background tasks (DR-036) |
| `lint.sh` | `shfmt` + `shellcheck` over `*.sh`/`*.bash`, `zsh -n` over `*.zsh`; truncates `report.txt` per run, exits non-zero on findings |
| `bash-preexec.sh` | vendored rcaloras bash-preexec (MIT); fallback for atuin < 18.18.x (DR-010, DR-025) |
| `embed.mjs` / `unembed.mjs` | embed files into a self-contained HTML page / extract them back |
| `termux-file-editor`, `termux-url-opener` | Termux hook scripts |

## 3. Startup chains per environment

Known login chains:

- Linux/bash: `~/.bash_profile` (login), `~/.bashrc` (non-login)
- Linux/zsh: `/etc/zshenv` → `~/.zshenv` → `~/.zprofile` → `~/.zshrc` →
  `~/.zlogin` → `~/.zlogout`
- Git Bash / MSYS2 (win32): `/etc/profile` → `~/.bash_profile` (login),
  `~/.bashrc` (non-login)
- Termux: `$PREFIX/etc/profile` → `~/.bashrc` (interactive bash, not
  posix/sh); login bash additionally reads `~/.bash_profile` — the
  `DOTFILES_SOURCED` guard makes the second entry a no-op and stops
  `20_core.bash`'s profile re-source from recursing into `~/.bashrc`
  (DR-027)
- PowerShell (win32): `$PROFILE` → `src-dotfiles.ps1` → `profile.d/*.ps1`
  (`40_completion.ps1` kubectl completion; `60_containers.ps1` dynamic
  KUBECONFIG; `70_history.ps1` atuin hooks)

Per-environment behavior:

- **Termux (Android):** `$PREFIX/etc/profile` sources `~/.bashrc` for
  interactive shells, and a login bash also reads `~/.bash_profile` — the
  guard makes the double-read a no-op. `deploy.sh` also creates
  `~/.termux/boot`, `~/.termux/widget/dynamic_shortcuts`,
  `~/.shortcuts/tasks` and `~/bin` (chmod 700) — the dirs are scaffolding
  (empty except the two background-task scripts `deploy.sh` copies into
  `~/.shortcuts/tasks/` from `shortcuts/tasks/`; DR-036). `~/.shortcuts/`
  stores Termux:Widget foreground scripts, `~/.shortcuts/tasks` background
  tasks; `dynamic_shortcuts` is scaffolded empty — drop scripts there and
  press the app's `CREATE SHORTCUTS` button. See the
  [termux-widget README](https://github.com/termux/termux-widget).
- **Fedora Silverblue:** standard login chain; `20_core.bash` sources
  `/etc/bashrc`. All POSIX/bash/zsh snippets are active.
- **WSL2 Fedora Linux 44:** standard chain plus `10_wsl2.sh` (active):
  `XDG_RUNTIME_DIR` trailing-slash normalization, `fstrim /` once per boot,
  `mount --make-shared /`, a bind mount of `/` at
  `/mnt/wsl/$WSL_DISTRO_NAME`, gnome-keyring startup. `80_path.sh`
  re-appends `/usr/lib/wsl/lib` when present.
- **Cloud shells (Google Cloud, Oracle OCI):** the standard login chain, but
  `20_core.bash` sources the cloud's own bashrc first
  (`/google/devshell/bashrc.google` resp. `/etc/bashrc.cloudshell`) and
  `80_path.sh` skips the DR-014 reset when those markers exist, so the
  provider's PATH is left exactly as the session was given it.
- **Git Bash / MSYS2 (win32):** `20_core.bash` sources `/etc/bash.bashrc`;
  `80_path.sh` appends `${SCOOP:-~/scoop}/shims` and
  `${LOCALAPPDATA:-…}/mise/{bin,shims}` — never a reset (DR-022.2, DR-029).
  atuin/kubectl are resolved from the `.exe` allowlist (DR-028);
  `60_containers.sh` joins KUBECONFIG with `;`.
- **Windows PowerShell 5.1 / Core 7.x:** `$PROFILE` → `src-dotfiles.ps1` →
  `profile.d/*.ps1` (DR-030) — the guard is session-local
  (`$global:DOTFILES_SOURCED`), the loop sources only `.ps1` snippets in the
  same 10_..90_ order, and nothing touches PATH. pwsh's `$PROFILE` lives
  under `Documents\PowerShell\…` and is wired separately from 5.1's
  `WindowsPowerShell\…`. PSReadLine ships with pwsh, so the atuin hook and
  kubectl completion work out of the box there.

## 4. The `profile.d/` contract

- **Ordering:** glob order, enforced by numeric prefixes
  `10_ … 20_ … 40_ … 50_ … 60_ … 70_ … 80_ … 90_` (DR-001).
- **Extensions:** `.sh` POSIX (sourced by every shell, dash-clean, DR-002);
  `.bash` bash-only; `.zsh` zsh-only; `.ps1` PowerShell-only (DR-030).
- **Isolation:** shell-exclusive files are filtered by the entrypoint *and*
  carry their own `$BASH_VERSION`/`$ZSH_VERSION` guard plus a stderr
  wrong-shell warning (DR-018).
- **Interactivity:** interactive-only work is gated on `case "$-" in *i*)`
  (DR-017); WSL2 privileged steps additionally on `$PS1`.
- **Hygiene:** snippets unset their scratch variables; the entrypoint unsets
  its helper function and loop variable (DR-019).

## 5. Tool wiring reference

- **atuin** (`70_history.{bash,zsh,ps1}`): resolved from an ordered
  allowlist — mise shims (XDG/user/system/`%LOCALAPPDATA%`), brew,
  scoop (`.exe`), Termux, `/usr/bin` — validated with `--version`, with a
  one-shot `mise use -g atuin` auto-provision for versionless mise shims
  (DR-016, DR-023, DR-026, DR-028). bash additionally sources the vendored
  `bash-preexec.sh` before `atuin init` (fallback for atuin < 18.18.x,
  DR-025). Invoked as `atuin init <shell> --disable-up-arrow`.
- **Completions** (`40_completion.*`): bash-completion framework + brew
  shellenv (the framework file is probed with `-r` — distros install it
  non-executable); per-tool cascade mise user shim → system mise shim →
  brew → system (`mise` itself: standalone POSIX installs → brew → system);
  `mise activate`, uv/uvx shell completion,
  `kubectl completion <shell>` via process substitution (bash/zsh) or
  `Out-String | Invoke-Expression` (PowerShell) (DR-021, DR-031, DR-034).
- **KUBECONFIG** (`60_containers.*`): if `~/.kube/config.d` exists *and
  contains files*, `KUBECONFIG` is the list of its files joined with the
  platform list separator; an empty or missing directory leaves an
  inherited KUBECONFIG untouched (DR-032, DR-034). PowerShell additionally
  sorts by name and emits no trailing separator (DR-032).
- **REPL history** (`70_history.sh`): `DUCKDB_HISTORY`, `NODE_REPL_HISTORY`
  (+ `NODE_REPL_HISTORY_SIZE=10000`), `SQLITE_HISTORY` point into
  `$XDG_STATE_HOME`; legacy `~/.duckdb_history`, `~/.node_repl_history`,
  `~/.sqlite_history` are appended onto the new location and removed.
  (`PYTHON_HISTORY` is prepared but commented out — needs Python ≥ 3.13.)
- **PATH** (`80_path.sh`): POSIX non-cloud hosts get a wholesale reset to
  mise shims + system dirs, then optional appends (Steam Deck bin,
  linuxbrew, `/usr/lib/wsl/lib`); Win32 and cloud/Termux never reset, Win32
  only appends existing scoop/mise dirs (DR-014, DR-022, DR-029, DR-033).

## 6. Data & side effects

| artifact | producer | consumer |
|---|---|---|
| `~/storage/shared/Documents/markor/ip.json` | `50_ip.sh` (Termux) | external Android app (Markor) |
| `$XDG_RUNTIME_DIR/.dotfiles-fstrim-$(id -u)` | `10_wsl2.sh` | fstrim once-per-boot throttle (tmpfs, gone on reboot) |
| `/mnt/wsl/$WSL_DISTRO_NAME` | `10_wsl2.sh` | other WSL2 distros (direct FS access) |
| `$XDG_STATE_HOME/{duckdb,node_repl,sqlite}_history` | `70_history.sh` | the respective REPLs |
| `~/.termux/boot`, `~/.termux/widget/dynamic_shortcuts`, `~/bin` | `deploy.sh` (Termux, empty dirs) | Termux:Widget / Termux:Boot |
| `~/.shortcuts/tasks/sshd.sh` | `deploy.sh` (copies `shortcuts/tasks/sshd.sh`) | Termux:Widget background task (sshd restart) |
| `~/.shortcuts/tasks/ip.sh` | `deploy.sh` (copies `shortcuts/tasks/ip.sh`) | Termux:Widget background task (ip.json refresh + toast) |
| `report.txt` | `lint.sh` | per-run shfmt/shellcheck/`zsh -n` log; truncated at each run |

## 7. Deployment & maintenance

- **Deploy:** `deploy.sh` copies `src-dotfiles.sh` onto
  `~/.bash_profile`/`~/.bashrc` (and `~/.zprofile`/`~/.zshrc` when zsh
  exists). After deploy the rc files *are* the entrypoint (copied, not
  symlinked — each stays self-contained). On Termux it additionally copies
  `shortcuts/tasks/{sshd,ip}.sh` into `~/.shortcuts/tasks/` (DR-036). The
  one supported extension point is `~/dotfiles/profile.d/`.
- **PowerShell wire-up** (manual, one line in `$PROFILE`):
  ```powershell
  . "$HOME\dotfiles\src-dotfiles.ps1"
  ```
- **Lint:** `lint.sh` runs `shfmt --write --indent 0 --binary-next-line
  --case-indent` and `shellcheck --check-sourced --external-sources
  --severity=style --enable=all --exclude=SC2292,SC2250` over
  `*.sh`/`*.bash` files, and `zsh -n` over `*.zsh` (shellcheck cannot
  parse zsh, SC1071).
  SC2292 (prefer `[[ ]]`) and SC2250 (prefer braced var refs) are excluded:
  style-only and incompatible with the POSIX-clean `*.sh` requirement.
  `report.txt` is truncated per run and the script exits non-zero when any
  tool reports findings (DR-034).
- **Embedding:** `node embed.mjs <files…>` produces a self-contained HTML
  page (plaintext as escaped `<pre>`, images as data URIs, other binaries
  as folded base64 with `-----BEGIN/END BASE64-----` armor);
  `node unembed.mjs <page.html> [outdir]` extracts them back.

## 8. Credits

This package bundles bash-preexec. Copyright (c) 2017 Ryan Caloras and
contributors. Full source code available at
<https://github.com/rcaloras/bash-preexec>, The MIT License.
