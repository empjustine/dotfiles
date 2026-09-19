# Dotfiles — Business Requirements (BRD)

This document states *what* the dotfiles must achieve for their owner and
*where* they must (and deliberately must not) work. *How* the system works is
covered in [system.md](system.md) (SRD); *why it is built the way it is* is
covered in [design.md](design.md) (TDD) and [../DECISIONS.md](../DECISIONS.md)
(decision log). Known documentation inconsistencies are tracked in
[known-issues.md](known-issues.md).

## 1. Purpose

Provide one consistent, predictable shell environment for a single owner
across every machine and shell they log into — desktops, WSL2, Termux on
Android, cloud shells, Git Bash on Windows, and native PowerShell — with:

- one place to author configuration,
- one deployment step,
- explicit, accepted limitations per platform instead of silent breakage.

## 2. Supported environments (scope)

The matrix below is the authoritative answer to "where does this run, and
what does it deliberately not do there" (DR references point into
`DECISIONS.md`). Every row runs the same `src-dotfiles.sh` → `profile.d/*`
loop — or its `src-dotfiles.ps1` analog — behind the `DOTFILES_SOURCED`
idempotency guard (DR-027); the columns show what differs.

| environment | shells | entrypoints | PATH policy | tools wired up |
|---|---|---|---|---|
| Termux (Android) | bash, zsh* | `$PREFIX/etc/profile` → `~/.bashrc`, `~/.bash_profile` | never reset — `$PREFIX/bin` owns it | atuin (Termux slot), kubectl, KUBECONFIG, ip.json |
| Fedora Silverblue | bash, zsh* | `~/.bash_profile`, `~/.bashrc`, `~/.zprofile`, `~/.zshrc` | DR-014 wholesale reset | mise, uv/uvx, kubectl, atuin, KUBECONFIG |
| WSL2 Fedora Linux 44 | bash, zsh* | same four | DR-014 reset, `/usr/lib/wsl/lib` re-appended | everything above + WSL2 plumbing (fstrim, mounts, keyring) |
| Cloud shells (Google Cloud, Oracle OCI) | bash (zsh optional on Google) | standard chain + cloud's own bashrc sourced | no reset — cloud shell owns it | none — cloud tooling left as-is |
| Git Bash / MSYS2 (win32) | bash, zsh* | `/etc/profile` → `~/.bash_profile`, `~/.bashrc` | append-only — never reset (DR-022.2, DR-029) | atuin/kubectl via `.exe` allowlist (DR-028), KUBECONFIG `;` |
| Windows PowerShell 5.1 | powershell | `$PROFILE` → `src-dotfiles.ps1` | n/a — entrypoint/snippets touch no PATH | atuin hook, kubectl completion, KUBECONFIG `;` |
| PowerShell Core 7.x | powershell | pwsh `$PROFILE` → `src-dotfiles.ps1` | n/a | same as 5.1 |

\* `deploy.sh` installs the zsh entrypoints only when `zsh` is present; on
platforms without zsh (fresh Silverblue, Git Bash) nothing is written to
`~/.zprofile`/`~/.zshrc`. `70_moratorium.sh` (npm/pip/uv/pnpm/mise release
moratorium env vars) applies in every POSIX environment.

### 2.1 Termux (Android) — accepted limitations

- PATH is never reset — the Android `$PREFIX` layout owns it.
- atuin's Termux build sits in a near-last allowlist slot, below any
  mise/brew install.
- `50_ip.sh` only writes `ip.json` when `~/storage/shared/Documents/markor`
  exists — `termux-setup-storage` must have been run.
- `90_navigation.zsh` keybindings need `TERM=xterm-256color`; other TERM
  values get zsh defaults.
- `10_wsl2.sh` is fully inert (no `$WSL_DISTRO_NAME`).

### 2.2 Fedora Silverblue — accepted limitations

- the DR-014 reset drops manual `$PATH` customizations — by design,
  including the skel's `~/.local/bin` and `~/bin` (plus `~/.bin` and
  `~/.shortcuts`); add PATH dirs from `profile.d/`, not rc files (DR-033).
- the skel `.bashrc`'s `~/.bashrc.d/*` loop is replaced by the `profile.d/`
  loop — migrate anything you had there (DR-033).
- flatpak-installed CLIs are not on the reset PATH; use `flatpak run` or add
  the export dirs yourself (`~/.local/share/flatpak/exports/bin`,
  `/var/lib/flatpak/exports/bin`).
- zsh is not preinstalled: the zsh entrypoints are skipped until
  `rpm-ostree install zsh` (plus a reboot).
- the root is immutable — deployment writes only to `$HOME`.

### 2.3 WSL2 (Fedora Linux 44) — accepted limitations

- the privileged steps are interactive-only (ssh host commands, scp and CI
  skip them) and need sudo/root.
- fstrim happens once per boot, by design (throttle stamp lives in tmpfs).
- the DR-014 reset drops the Windows PATH passthrough (`appendWindowsPath`
  in `/etc/wsl.conf`); Windows commands must be invoked by full `/mnt/c/…`
  path or by re-adding the dirs (interop itself is unaffected).
- WSL1 is not supported — the bind-mount/shared-mount logic is WSL2-only.

### 2.4 Cloud shells (Google Cloud, Oracle OCI) — accepted limitations

"Supported, but deliberately thin": the dotfiles respect the provider's
default tooling path and default sourcing and add nothing on top.

- no PATH manipulation of any kind — cloud tooling keeps its provider-set
  locations.
- atuin/kubectl hooks and completions only fire if the binary happens to sit
  in an allowlisted location (mise shims, brew, `/usr/bin`) — the cloud's
  own placements are intentionally not probed.
- `10_wsl2.sh` and `50_ip.sh` are inert; `60_containers.sh` still applies if
  `~/.kube/config.d` exists (rare); `70_moratorium.sh` applies as anywhere.
- both shells are ephemeral VMs: anything outside `$HOME` is lost when the
  session ends; re-run `deploy.sh` after the provider resets the image.
- Google Cloud Shell offers zsh as an alternative shell; only the deploy
  gate changes with that choice (the zsh entrypoints are installed when zsh
  is detected) — the snippet set does not.

### 2.5 Git Bash / MSYS2 (win32) — accepted limitations

- the Windows PATH is only ever appended-to with dirs that exist — a fresh
  install before the first `scoop install`/mise run has neither, and nothing
  is added.
- hooks and completion trust only scoop/mise shim locations; choco/winget
  installs of atuin/kubectl are not picked up (add a candidate if you use
  them).
- zsh: Git Bash ships none, so the entrypoints are skipped; MSYS2 users who
  install zsh get them.
- XDG vars stay at Unix-y defaults (DR-024) — native Windows tools are
  unaffected.
- Cygwin matches the `*CYGWIN*` case but is not a tested target.

### 2.6 Windows PowerShell 5.1 / PowerShell Core 7.x — accepted limitations

- the profile must pass the ExecutionPolicy (typically `RemoteSigned`); a
  downloaded `src-dotfiles.ps1` needs `Unblock-File` first.
- hosts without PSReadLine (ISE, bare hosts) skip the atuin hook silently.
- snippets are ASCII-only by construction: 5.1 reads non-BOM files as ANSI.
- 5.1 compatibility is by construction (3.0+ feature set); no 5.1 CI host
  exercises it.
- running pwsh on Linux/macOS sources the snippets too, but 40/70 are inert
  there (Windows gate) and 60 switches to `:` — only Windows is supported.

## 3. Functional requirements

- **REQ-1 Single extension point.** All shell configuration lives in
  `profile.d/` numbered snippets; users never edit generated rc files
  (DR-001, DR-033).
- **REQ-2 Tool wiring.** atuin history hooks, tab completion (kubectl,
  mise, uv/uvx, brew, bash-completion framework) and dynamic
  KUBECONFIG are set up automatically where the tools exist in trusted
  locations.
- **REQ-3 REPL/history hygiene.** REPL history for duckdb/node/sqlite is
  redirected to `$XDG_STATE_HOME`, migrating legacy `~/.<tool>_history`
  files on first use.
- **REQ-4 WSL2 maintenance.** On WSL2: periodic `fstrim /`, shared root
  mount propagation, cross-distro bind mount, gnome-keyring Secret Service
  bootstrap, `XDG_RUNTIME_DIR` normalization (DR-007).
- **REQ-5 LAN IP export (Termux).** Write `ip --json addr` to the Markor
  Documents folder for an external app to read; interactive shells only
  (DR-009, DR-034).
- **REQ-6 Supply-chain moratorium.** mise, npm, pnpm and uv lag "latest" by
  a 3-day release-age window (pip's window variable,
  `PIP_UPLOADED_PRIOR_TO`, is prepared but currently inactive); npm
  lifecycle scripts are disabled globally; pip installs are confined to
  venvs (DR-005, DR-006).
- **REQ-7 Termux:Widget scaffolding.** Deploy creates the Termux:Widget
  script directories and copies the two background-task scripts
  (`shortcuts/tasks/sshd.sh`, `shortcuts/tasks/ip.sh`) into
  `~/.shortcuts/tasks/` (DR-036).

## 4. Non-functional requirements / constraints

- **NFR-1 Idempotent startup.** The whole chain is safe to re-enter:
  double reads, re-sourcing and Termux's recursive profile chain must be
  no-ops (DR-027).
- **NFR-2 No arbitrary binaries trusted.** External tools (atuin, kubectl,
  mise, uv, …) are resolved only from an explicit, ordered allowlist of
  install locations — never an arbitrary `$PATH` lookup (DR-016, DR-026).
- **NFR-3 POSIX cleanliness.** `*.sh` snippets must run under `dash`
  (Debian `/etc/profile` semantics): no `[[`, no `<(…)`, no `local`, no
  `source` (DR-002).
- **NFR-4 Interpreter isolation.** Bash-only logic must never run under zsh
  and vice-versa, with a stderr warning if it is attempted (DR-018);
  interactive-only steps must not run in non-interactive sessions (ssh,
  scp, CI) (DR-017).
- **NFR-5 No foreign-config mutation.** Deploy must not write to other
  tools' configuration (npm, mise, uv config) — policy travels via env vars
  (DR-011).
- **NFR-6 No state leakage.** Snippet-internal scratch variables are unset
  before returning; only intentional exports persist in the session
  (DR-019).
- **NFR-7 PowerShell breadth.** `src-dotfiles.ps1` and `*.ps1` snippets
  must run on both Windows PowerShell 5.1 and PowerShell Core 7.x (3.0+
  feature set, ASCII-only) (DR-030).

## 5. Non-goals

- Honoring the stock per-user extension points (`~/.bashrc.d`,
  `~/.local/bin`, `~/bin`, `~/.bin`, `~/.shortcuts`) as config or PATH
  sources — `profile.d/` is the single extension point (DR-033).
- PATH management inside cloud shells or Termux — the provider owns it.
- WSL1, untested Cygwin, choco/winget tool discovery on Windows.
- Generalizing hardcoded personal identifiers (an OCI user OCID, a Steam
  Deck volume UUID) — accepted as brittle-but-explicit (DR-008).

## 6. Accepted risks

- **DR-008 (PII, identifiers).** A Steam Deck volume UUID is tracked in
  `80_path.sh`, and an OCI user OCID is hardcoded in `60_containers.sh` —
  the latter currently commented out (DR-008 status note). They are
  identifiers, not credentials; disclosure risk is accepted for stable,
  explicit config paths.
- **DR-009 (LAN IP export).** Writing every visited host's LAN IPs into a
  shared Android Documents folder is accepted: on-device apps can already
  read the device's IPs via OS APIs, and the data is LAN-local, not
  credentials.
- **DR-005 (release lag).** A 3-day moratorium window trades same-day
  malicious-release protection for a smaller breakage/freshness cost
  (down from an earlier 7-day window).
