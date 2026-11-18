---
id: system
type: architecture-design
status: active
title: "Dotfiles — systems reference (SRD)"
parent: index
references: [goal, design, execution-map, decision-log]
---
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
        │  (each is a copy of src-dotfiles.sh)
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
| `profile.d/10_wsl2.sh` | WSL2 plumbing: `XDG_RUNTIME_DIR` normalization, then (interactive, one per-boot stamp) tmpfs ownership, `fstrim /`, shared-root propagation, cross-distro bind mount, gnome-keyring (DR-007, DR-038) |
| `profile.d/20_core.bash` | sources the distro/cloud/system bashrc (`/etc/bashrc`, `/etc/bash.bashrc`, Termux profile, Google/Oracle cloud bashrc) (DR-020) |
| `profile.d/40_completion.{bash,zsh}` | tab completion: bash-completion framework / `compinit`, brew shellenv, mise activate, uv/uvx, kubectl — identical allowlist cascade + mise-shim trust gate in both (DR-021, DR-026, DR-038) |
| `profile.d/60_containers.sh` | dynamic `KUBECONFIG` from `~/.kube/config.d` (DR-032) |
| `profile.d/70_history.{bash,zsh}` | atuin history hooks: allowlisted discovery, `--version` smoke test, `atuin init <shell>` (DR-016, DR-026) |
| `profile.d/70_history.sh` | REPL history relocation into `$XDG_STATE_HOME` + legacy-file fold (DR-003, DR-038) |
| `profile.d/70_moratorium.sh` | supply-chain env vars: release-age windows, `NPM_CONFIG_IGNORE_SCRIPTS`, `PIP_REQUIRE_VIRTUALENV` (DR-005, DR-006, DR-011) |
| `profile.d/80_path.sh` | PATH policy: wholesale reset (DR-014) except on cloud shells/Termux; `ANDROID_HOME` |
| `profile.d/90_navigation.zsh` | xterm-256color keybindings (word-jump, Home/End/Delete) |
| `shortcuts/tasks/sshd.sh` | Termux:Widget background task — restart sshd and toast its status (was embedded in `termux-shortcuts.html`); copied verbatim to `~/.shortcuts/tasks/sshd.sh` by `deploy.sh` (DR-036) |
| `shortcuts/tasks/ip.sh` | Termux:Widget background task — **sole producer of `ip.json`** for Markor, plus a toast of the primary IPv4 (DR-009, DR-036, DR-038); copied to `~/.shortcuts/tasks/ip.sh` by `deploy.sh` |
| `deploy.sh` | copies `src-dotfiles.sh` onto the rc targets (zsh targets only when zsh exists); Termux:Widget dir scaffolding + `shortcuts/tasks/*.sh` background tasks (DR-036) |
| `lint.sh` | `shfmt` + `shellcheck` over `*.sh`/`*.bash`, `zsh -n` over `*.zsh`, then the docs gate; truncates `report.txt` per run, exits non-zero on findings |
| `docs/spec-check.mjs` | the documentation gate: frontmatter graph, DR citations, links/anchors/§ cites, inventory vs tree (DR-042, [spec-standard.md](spec-standard.md)) |
| `embed.mjs` / `unembed.mjs` | embed files into a self-contained HTML page / extract them back |
| `termux-file-editor`, `termux-url-opener` | Termux hook scripts |

## 3. Startup chains per environment

Known login chains:

- Linux/bash: `~/.bash_profile` (login), `~/.bashrc` (non-login)
- Linux/zsh: `/etc/zshenv` → `~/.zshenv` → `~/.zprofile` → `~/.zshrc` →
  `~/.zlogin` → `~/.zlogout`
- Termux: `$PREFIX/etc/profile` → `~/.bashrc` (interactive bash, not
  posix/sh); login bash additionally reads `~/.bash_profile` — the
  `DOTFILES_SOURCED` guard makes the second entry a no-op and stops
  `20_core.bash`'s profile re-source from recursing into `~/.bashrc`
  (DR-027)

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
- **WSL2 Fedora Linux 44 (first-class, DR-038):** standard chain plus
  `10_wsl2.sh` (active). Non-interactive sessions (`ssh host cmd`, `scp`,
  CI) stop after the `XDG_RUNTIME_DIR` trailing-slash normalization; an
  interactive login runs the privileged block **once per boot** (stamp
  `$XDG_RUNTIME_DIR/.dotfiles-wsl-<boot_id>-<uid>`): tmpfs ownership,
  `fstrim /`, `mount --make-shared /`, bind mount of `/` at
  `/mnt/wsl/$WSL_DISTRO_NAME`, then gnome-keyring startup (only while
  `GNOME_KEYRING_CONTROL` is unset). `80_path.sh` appends
  `/usr/lib/wsl/lib` when present.
- **Cloud shells (Google Cloud, Oracle OCI):** the standard login chain, but
  `20_core.bash` sources the cloud's own bashrc first
  (`/google/devshell/bashrc.google` resp. `/etc/bashrc.cloudshell`) and
  `80_path.sh` skips the DR-014 reset when those markers exist, so the
  provider's PATH is left exactly as the session was given it.
- **Native Windows shells (Git Bash / MSYS2 / Cygwin, PowerShell):**
  out of scope. The PowerShell entrypoint/snippets and every `.exe`/scoop/
  `%LOCALAPPDATA%`/Win32-separator code path were removed (DR-038); WSL2 —
  a Linux guest — is the supported way to use the dotfiles on a Windows
  host.

## 4. The `profile.d/` contract

- **Ordering:** glob order, enforced by numeric prefixes
  `10_ … 20_ … 40_ … 50_ … 60_ … 70_ … 80_ … 90_` (DR-001).
- **Extensions:** `.sh` POSIX (sourced by every shell, dash-clean, DR-002);
  `.bash` bash-only; `.zsh` zsh-only — and these must not be merged into
  `.sh`, because a `.sh` snippet runs under `emulate -L ksh` in zsh and
  shell-generated code breaks there (DR-040). A naming convention that would
  hoist shell/interactivity gating into the entrypoint is *proposed*, not
  applied (DR-039, [execution-map.md](execution-map.md) §8).
- **Isolation:** shell-exclusive files are filtered by the entrypoint *and*
  carry their own `$BASH_VERSION`/`$ZSH_VERSION` guard plus a stderr
  wrong-shell warning (DR-018).
- **Interactivity:** interactive-only work is gated on `case "$-" in *i*)`
  (DR-017) — now the only interactivity test in the tree (the old `$PS1`
  gate in `10_wsl2.sh` is gone, DR-038).
- **Hygiene:** snippets unset their scratch variables; the entrypoint unsets
  its helper function and loop variable (DR-019).

## 5. Tool wiring reference

- **atuin** (`70_history.{bash,zsh}`): resolved from an ordered
  allowlist — mise shims (XDG/user/system), brew, Termux, `/usr/bin` —
  validated with `--version`, with a one-shot `mise use -g atuin`
  auto-provision for versionless mise shims (DR-016, DR-026). atuin ≥ 18.18.x bundles its own
  bash-preexec (V0.7.0) and auto-loads it at init time when no other
  preexec backend (ble.sh, external bash-preexec) is present — the
  dotfiles source nothing, so the bundled copy is the only backend
  (DR-025, DR-037). Invoked as `atuin init <shell> --disable-up-arrow`.
- **Completions** (`40_completion.bash`, `40_completion.zsh`): same
  allowlist cascade and the same mise-shim trust gate in both files
  (byte-identical block, DR-038); bash-completion framework / `compinit` +
  brew shellenv (the framework file is probed with `-r` — distros install
  it non-executable); `mise activate <shell>`, uv/uvx shell completion,
  `kubectl completion <shell>` — all eval'd as `eval "$(<tool> …)"`
  (DR-021, DR-026, DR-034).
- **KUBECONFIG** (`60_containers.sh`): if `~/.kube/config.d` exists *and
  contains files*, `KUBECONFIG` is the list of its files joined with `:`;
  an empty or missing directory leaves an inherited KUBECONFIG untouched
  (DR-032, DR-034, DR-038).
- **REPL history** (`70_history.sh`): `DUCKDB_HISTORY`, `NODE_REPL_HISTORY`
  (+ `NODE_REPL_HISTORY_SIZE=10000`), `SQLITE_HISTORY` point into
  `$XDG_STATE_HOME`; legacy `~/.duckdb_history`, `~/.node_repl_history`,
  `~/.sqlite_history` are appended onto the new location and removed.
  (`PYTHON_HISTORY` is prepared but commented out — needs Python ≥ 3.13.)
- **PATH** (`80_path.sh`): non-cloud, non-Termux hosts get a wholesale
  reset to mise shims + system dirs, then optional appends (Steam Deck bin,
  linuxbrew, `/usr/lib/wsl/lib`); cloud shells and Termux are never touched
  (DR-014, DR-033).

## 6. Data & side effects

| artifact | producer | consumer |
|---|---|---|
| `~/storage/shared/Documents/markor/ip.json` | `shortcuts/tasks/ip.sh` (Termux:Widget background task — no shell startup writes it) | external Android app (Markor) |
| `$XDG_RUNTIME_DIR/.dotfiles-wsl-<boot_id>-$(id -u)` | `10_wsl2.sh` | once-per-boot gate for the whole privileged WSL2 block (tmpfs, gone on reboot) |
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
- **Lint:** `lint.sh` runs `shfmt --write --indent 0 --binary-next-line
  --case-indent` and `shellcheck --check-sourced --external-sources
  --severity=style --enable=all --exclude=SC2292,SC2250` over
  `*.sh`/`*.bash` files, `zsh -n` over `*.zsh` (shellcheck cannot parse zsh,
  SC1071), and finally the documentation gate (`node docs/spec-check.mjs`,
  DR-042; contract in [spec-standard.md](spec-standard.md)).
  SC2292 (prefer `[[ ]]`) and SC2250 (prefer braced var refs) are excluded:
  style-only and incompatible with the POSIX-clean `*.sh` requirement.
  `report.txt` is truncated per run and the script exits non-zero when any
  tool reports findings (DR-034).
- **Embedding:** `node embed.mjs <files…>` produces a self-contained HTML
  page (plaintext as escaped `<pre>`, images as data URIs, other binaries
  as folded base64 with `-----BEGIN/END BASE64-----` armor);
  `node unembed.mjs <page.html> [outdir]` extracts them back.

## 8. Credits

*This section is intentionally empty — the last bundled third-party
component (rcaloras' bash-preexec, MIT) was removed with the atuin ≥
18.18 floor (DR-037); see the git history and DR-010/DR-025 for its
time in the tree.*
