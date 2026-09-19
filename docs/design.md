# Dotfiles — Technical Design (TDD)

This document explains *why the system is built the way it is*: the design
mechanisms, the constraints that shaped them, and the invariants that must
not be broken. The full, dated decision log (context / decision /
consequences per DR-###) lives in [../DECISIONS.md](../DECISIONS.md); this
document groups and summarizes it. *What* the system must do is in
[requirements.md](requirements.md) (BRD); *how it works* is in
[system.md](system.md) (SRD). Known documentation inconsistencies are tracked
in [known-issues.md](known-issues.md).

## 1. Architecture: one entrypoint, one drop-in directory

**Decision:** all real configuration lives in `profile.d/<NN>_name.{sh,bash,zsh,ps1}`;
the four POSIX rc files (`~/.bash_profile`, `~/.bashrc`, `~/.zprofile`,
`~/.zshrc`) are byte-identical copies of a single entrypoint, `src-dotfiles.sh`,
that merely loops over that directory; native PowerShell has its own analog,
`src-dotfiles.ps1`, wired by a one-line dot-source in `$PROFILE` rather than a
copy (DR-001, DR-004, DR-015, DR-030).

- Why a drop-in dir: one deterministic ordering for every shell, and
  trivial entrypoints (DR-001).
- Why copies, not symlinks: each rc file stays self-contained, and hosts
  that treat the targets differently (Termux double-read) still work.
- Why `bash_profile` does not source `bashrc`: the loop *is* the content,
  so the "login inherits interactive setup" convention is moot; deviating
  from it is cheaper than maintaining a second path (DR-004).
- Consequence: a non-standard layout; the skel `~/.bashrc.d/*` loop and its
  `~/.local/bin`/`~/bin` PATH prepend are replaced by `profile.d/` (DR-033).

### Cross-cutting packaging constraint

`/etc/profile` on Debian/Fedora loops `/etc/profile.d/*.sh` **under dash**,
and only for **login** shells. Debian's `/etc/zsh/zprofile` does NOT source
`/etc/profile` (Fedora's does). So a pure `/etc/profile.d` drop-in covers
bash/ksh login everywhere and zsh login on Fedora, but not zsh on Debian and
never non-login interactive shells — per-user entrypoints remain mandatory
(feeds DR-001/DR-002).

## 2. Snippet extension split and interpreter isolation

**Decision:** `.sh` = POSIX, sourced by *both* shells; `.bash`/`.zsh` =
shell-specific remainder (DR-002). Isolation is enforced in two independent
layers plus a warning (DR-018):

1. the entrypoint only sources `.bash` under `BASH_VERSION` and `.zsh` under
   `ZSH_VERSION`;
2. each shell-exclusive file re-checks its own guard;
3. a wrong-shell source prints a stderr warning instead of failing silently.

**Why `.sh` must stay dash-clean** (no `[[`, `<(…)`, `local`, `source`):
Debian's `/etc/profile` may run them under `dash`, and the entrypoint itself
may be deployed to `/etc/profile.d`.

**Interactive gating** uses `case "$-" in *i*)` — the canonical test — so
snippets never fire in `ssh host command`, `scp`, or CI (DR-017).

## 3. Zsh sourcing of POSIX snippets: `emulate -L ksh`

**Decision:** under zsh each `.sh` source is wrapped in a function doing
`emulate -L ksh` first (DR-003):

```zsh
_src_ksh() { emulate -L ksh; . "$1"; }
```

- **Why a function wrapper:** `emulate -L` scopes the option change to the
  function so ksh behaviour does not leak into the rest of the shell, while
  ksh-style (non-function-local) assignment lets the sourced file's exports
  propagate into the interactive shell (verified empirically for `FOO`,
  `PATH`, exported vars).
- **Why not `emulate sh`:** it would also work, but `ksh` was chosen for
  tolerance of bash-ish idioms. Do not "clean this up" to `emulate sh`
  without re-verifying export propagation.

## 4. Re-entrancy guard (`DOTFILES_SOURCED`)

**Decision:** the entrypoint sets `DOTFILES_SOURCED=1` and returns early on
re-entry (DR-027).

- **The hazard:** on Termux, `$PREFIX/etc/profile` sources `~/.bashrc`
  itself, and `20_core.bash` sources that same profile for non-login shells
  → unbounded recursion (bashrc → 20_core → /etc/profile → bashrc → …);
  separately, login bash reads `~/.bash_profile` after `/etc/profile`, so
  every snippet would run twice.
- **Why the flag is never unset:** it must survive across all rc files
  sourced within one shell process. Child shells (nested bash, ssh, tmux
  panes) are new processes and correctly install their own hooks.
- **Why the flag is set before the loop:** the loop re-enters this file
  (20_core → /etc/profile → ~/.bashrc), so the guard must already be up.
- **PowerShell analog:** `$global:DOTFILES_SOURCED`, deliberately a
  session-local variable, not an env var — same process-locality semantics
  (DR-030).

## 5. Tool discovery: ordered allowlist cascades

**Decision:** external tools (atuin, kubectl, mise, uv) are resolved
only from an explicit, ordered allowlist of install locations; an arbitrary
`command -v <tool>` from `$PATH` is intentionally never trusted (DR-016).

- **Cascade order** (first `-x` match wins). The two discovery loops differ
  slightly (DR-034); neither ever probes a bare `command -v <tool>`:
  - `_dotfiles_tool` (`40_completion.{bash,zsh}`): mise user shim (full-string
    default, then `$XDG_DATA_HOME` form) → `%LOCALAPPDATA%` mise shim (`.exe`,
    Windows-only) → system mise shim (`MISE_SYSTEM_DATA_DIR` form, then
    full-string default) → brew → scoop shim (`.exe`, Windows-only) →
    `/usr/bin`.
  - atuin loop (`70_history.{bash,zsh}`): mise user shim (`$XDG_DATA_HOME`
    form, then full-string default) → `%LOCALAPPDATA%` mise shim (`.exe`) →
    system mise shim (env-var form, then full-string default) → brew → scoop
    shim (`.exe`) → Termux → `/usr/bin`.
  Literal defaults are listed alongside their env-var forms so the default
  install locations are always searched even when the vars point elsewhere;
  Termux and the system slots are fallback-only.
- **Why `--version` smoke tests:** a mise shim can exist yet have no version
  selected (`mise ERROR No version is set for shim: atuin`, exit 1). The
  binary must be proven to run before it is trusted; versionless mise shims
  get a one-shot `mise use -g atuin` auto-provision and re-check.
- **Why mise-shim probes require a resolvable mise** (`40_completion.bash`):
  shims only work while the mise binary itself is resolvable; otherwise a
  broken shim would be selected and shadow later candidates (DR-026).
  Resolvable means `command -v mise` *or* a mise binary found by the
  allowlisted `_dotfiles_mise` probe — snippets run before `80_path.sh`, so
  on a fresh login neither PATH nor brew/system mise may exist yet, and
  `_dotfiles_mise` gained the standalone POSIX locations to cover that
  (DR-034).
- **Why `.exe` is embedded instead of probed as a fallback** (DR-028): the
  original two-probe fallback paid an extra `-x` stat per candidate on every
  platform for a branch that only fires on Win32. PE shims have no
  extensionless twin, so embedding the spelling in the Windows-only
  candidates is equivalent and cheaper.
- **Why `bash-preexec.sh` is still vendored:** atuin ≥ 18.18.x bundles its
  own bash-preexec and auto-loads it when none is present, so the vendored
  copy is redundant there — but it is kept as the fallback for older atuin
  (DR-010, DR-025). When the atuin floor moves to ≥ 18.18.x, delete it.

## 6. PATH policy: three regimes

**Decision:** PATH handling differs deliberately per regime (DR-014,
DR-022.2, DR-029, DR-033):

1. **POSIX desktops/WSL2 — wholesale reset** to an explicit list (mise
   shims first, then `/usr/local/...`, `/usr/...`) plus a few optional
   appends. Predictability beats preservation: entries added elsewhere
   (snap, games, GUI session) are dropped *by design*, including the stock
   per-user dirs (`~/.local/bin`, `~/bin`, `~/.bin`, `~/.shortcuts`) —
   `profile.d/` is the only supported extension point (DR-033).
2. **Win32 — append-only, never reset.** PATH is owned by Windows
   (System32, per-user dirs, scoop); a reset would make native executables
   unreachable. Only existing scoop shim and mise (`%LOCALAPPDATA%\mise`)
   dirs are appended.
3. **Cloud shells & Termux — untouched.** The provider pre-builds a correct
   PATH ("don't mangle cursed $PATH"); detection is via the cloud bashrc
   markers resp. the Termux prefix.

**Why XDG vars stay at Unix defaults on Win32** (no remap to
`%LOCALAPPDATA%`): one set of defaults across platforms keeps behavior
predictable; the places that actually need Windows dirs probe
`${LOCALAPPDATA:-…}` / `${SCOOP:-…}` directly (DR-023, DR-024). Caveat: if
`SCOOP`/`LOCALAPPDATA` are exported Windows-style (`C:\...`), `-x` probes
rely on msys path conversion; leaving them unset avoids that entirely.

## 7. Supply-chain moratorium via env vars

**Decision:** release-age cooldowns and hardening are expressed purely as
environment variables in `70_moratorium.sh` — never by mutating other
tools' config files (DR-005, DR-006, DR-011).

- Uniform 3-day window: `MISE_MINIMUM_RELEASE_AGE=3d`,
  `UV_EXCLUDE_NEWER="3 days"`, `PIP_UPLOADED_PRIOR_TO` (commented; computed
  form), `npm_config_min_release_age=3`,
  `pnpm_config_minimum_release_age=4320` (minutes).
- Why lowercase npm/pnpm vars: npm/pnpm read them case-insensitively; the
  uppercase duplicates are kept commented — they work but are redundant and
  heavy-handed.
- `NPM_CONFIG_IGNORE_SCRIPTS=true` disables lifecycle scripts globally
  (supply-chain hardening; packages needing install scripts need explicit
  opt-in). `PIP_REQUIRE_VIRTUALENV=true` confines pip installs to venvs.
- Why env vars instead of `deploy.sh` mutation: no clobbering of tool-owned
  config, and the policy travels with the shell, not the install host.

## 8. WSL2 hardening steps (`10_wsl2.sh`)

Each step exists because of a specific WSL2 quirk (DR-007):

1. **`XDG_RUNTIME_DIR` trailing-slash strip** — WSL2 reports
   `/run/user/1000/` (real Linux: without the slash); the extra `/` would
   double up in later path joins (fstrim stamp path).
2. **Throttled `sudo fstrim /`** — the root lives on a grow-only VHDX;
   the stamp file in `XDG_RUNTIME_DIR` (tmpfs) makes it once-per-boot, on
   top of systemd timers.
3. **`mount --make-shared /`** — WSL2 defaults `/` to *private* propagation,
   which breaks rootless Podman mounts.
4. **Bind mount `/` at `/mnt/wsl/$WSL_DISTRO_NAME`** — gives other distros a
   direct path to this filesystem instead of round-tripping through
   Windows (DrvFS/9p).
5. **gnome-keyring `--components=secrets`** — bootstrap a Secret Service
   provider so libsecret apps work without a desktop session.

All steps are interactive-only (`$PS1`) and idempotent; the owner is a
passwordless sudoer there, which is what makes the `sudo` calls acceptable.

## 9. PowerShell flow (`src-dotfiles.ps1`, `*.ps1` snippets)

**Decision:** a mirror entrypoint sourcing only `*.ps1` snippets, same
guard/root-resolution/loop contract (DR-030, DR-031, DR-032).

- Compatibility by construction with 5.1 and 7.x: 3.0+ feature set
  (`$PSScriptRoot`), `$env:OS -eq 'Windows_NT'` instead of `$IsWindows` so
  one file serves both generations, ASCII-only (5.1 reads non-BOM as ANSI),
  `return`-based guard valid under dot-sourcing.
- Hooks wrap the `Invoke-Expression` of generated init blobs in `try/catch`:
  a PSReadLine-less host (ISE, bare hosts) must not break the session.
- KUBECONFIG deltas vs the sh version: sorted by name (deterministic, unlike
  `find` order) and no trailing separator (kubectl treats empty entries as
  "no file" either way; the sh version's trailing separator is harmless but
  noisy).

## 10. Invariants & gotchas (do-not-break list)

- `.sh` snippets stay dash-clean; no bashisms, no `source` (DR-002).
- `DOTFILES_SOURCED` is never unset or exported (DR-027).
- `emulate -L ksh` stays inside its function wrapper (DR-003).
- No tool is ever trusted from an arbitrary `$PATH` lookup (DR-016).
- The Windows PATH is only ever appended to, and only with existing dirs
  (DR-022, DR-029).
- The stock per-user PATH dirs are never re-added by the reset (DR-033).
- `deploy.sh` only ever copies `src-dotfiles.sh` (plus zsh targets) and the
  `shortcuts/tasks/*.sh` background tasks (Termux-only; DR-036); it does
  not copy `profile.d/` or `bash-preexec.sh` — extending it would risk
  stale copies on previously-provisioned hosts (DR-016).
- Snippet scratch variables are unset/removed on scope exit (DR-019,
  DR-034 — including the PowerShell flow).
- `*.ps1` snippets stay ASCII-only and 5.1-compatible (DR-030).
- An empty `~/.kube/config.d` never clobbers an inherited KUBECONFIG
  (DR-034).

## 11. Known debt / accidentals

- Hardcoded personal identifiers — the Steam Deck volume UUID in
  `80_path.sh` is active; the OCI user OCID block in `60_containers.sh` is
  currently commented out. Brittle either way; generalization recipe in
  DR-008.
- `50_ip.sh` writes to a synced Android folder — accepted, alternative
  location in DR-009.
- `bash-preexec.sh` vendoring is obsolete for atuin ≥ 18.18.x — delete when
  the floor moves (DR-010, DR-025).
- `PYTHON_HISTORY` wiring is ready but inert until Python ≥ 3.13 is
  standard (`70_history.sh`).
