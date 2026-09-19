# Dotfiles Decision Records

These are short decision records (ADR-lite) capturing the *surprising*,
non-obvious, or load-bearing choices in this dotfiles repo, plus a few
accidental artifacts that should be fixed. Format:

```
DR-### | Title | Status | Date (YYYY-MM-DD)
  Context    — why this exists / the constraints
  Decision   — what was chosen
  Consequences — what it buys, what it costs, and caveats
```

Status values: `Accepted` (deliberate), `Accidental` (mistake / tech debt),
`Proposed` (suggested change not yet applied).

---

## DR-001 | One `profile.d/` drop-in dir, numbered prefixes | Accepted | 2025-04-22

- **Context:** Bash and Zsh each have different login/non-login file names
  (`~/.bash_profile`, `~/.bashrc`, `~/.zprofile`, `~/.zshrc`). We want one place
  for the real config that every shell reads in a deterministic order.
- **Decision:** Put all logic in `profile.d/<NN>_name.{sh,bash,zsh}` and have the
  four entrypoints merely loop over that directory. Numeric prefixes enforce
  ordering (10 WSL2 → 20 core → 40 completion → … → 90 navigation).
- **Consequences:** Ordering is explicit and easy to reason about. The four
  entrypoints become trivial. Cost: a non-standard layout vs. editing the shell
  rc files directly.

## DR-002 | Three extensions: `.sh` / `.bash` / `.zsh` | Accepted | 2025-04-22

- **Context:** Some snippets are shell-agnostic POSIX; some need bashisms
  (process substitution, `source <(kubectl …)`); some need zshisms (`compinit`,
  `bindkey`).
- **Decision:** `.sh` = POSIX, sourced by *both* shells; `.bash`/`.zsh` = the
  shell-specific remainder. The entrypoint only sources the files whose
  extension matches the running shell (`.bash` skipped under zsh, `.zsh` skipped
  under bash).
- **Consequences:** Genuinely shared config lives once. **Constraint:** every
  `.sh` file MUST stay dash-clean (POSIX), because `/etc/profile` on Debian runs
  them under `dash` — no `[[`, no `<(…)`, no `local`, no `source`. Current
  `.sh` files satisfy this.

## DR-003 | Zsh sources POSIX `.sh` via `emulate -L ksh` (not `emulate sh`) | Accepted | 2025-12-06

- **Context:** Sourcing a POSIX file directly in zsh is unsafe (no word
  splitting, different glob/array semantics). We also need variables/exports
  set by those files to *escape* into the interactive shell.
- **Decision:** Wrap each `.sh` source in a function that does `emulate -L ksh`
  first:
  ```zsh
  _src_ksh() { emulate -L ksh; . "$1"; }
  ```
  The function wrapper is essential: `emulate -L` scopes the option change to the
  function so it does not leak ksh behaviour into the rest of the shell, while
  ksh-style (non-function-local) assignment lets the sourced file's `export`s
  propagate. Verified empirically: `FOO`, `PATH`, `export`-ed vars set inside the
  sourced file are visible after the function returns.
- **Consequences:** Works, but `ksh` is broader than strictly needed — `emulate
  sh` also propagates exports and is closer to POSIX. `ksh` was likely chosen for
  extra tolerance of bash-ish idioms. Low risk either way; documented so it is
  not "cleaned up" to `emulate sh` and accidentally regressed.

## DR-004 | `bash_profile` and `bashrc` are byte-identical; `bash_profile` does NOT source `bashrc` | Accepted | 2025-04-22

- **Context:** Convention says `~/.bash_profile` should `. ~/.bashrc` so login
  shells inherit interactive setup. Here both files just loop `profile.d/`.
- **Decision:** Both entrypoints contain the identical loop, and `bash_profile`
  intentionally does *not* source `bashrc`. Because the loop is the entire
  content, login and non-login bash both get the same environment either way.
- **Consequences:** Simpler mental model (one loop, everywhere) at the cost of
  deviating from the "bash_profile sources bashrc" convention. If a user later
  adds personal lines to `~/.bashrc` they will *not* appear in login shells —
  acceptable here because all real config lives in `profile.d/`.

## DR-005 | "Dependency moratorium": a 3-day version cooldown | Accepted | 2025-12-02

- **Context:** Freshly-published package releases are the highest-risk window for
  supply-chain attacks and accidental breakage. We want to lag "latest" by a
  fixed horizon across every toolchain.
- **Decision:** `70_moratorium.sh` (POSIX, shared) sets a uniform **3-day** window
  (aligned with the coding-agent runtime environment as of 2026-07):
  - `MISE_MINIMUM_RELEASE_AGE="3d"`
  - `UV_EXCLUDE_NEWER="3 days"` and `PIP_*` variants (`PIP_UPLOADED_PRIOR_TO` is prepared as a commented-out computed form in `70_moratorium.sh` — not currently active; `UV_EXCLUDE_NEWER` carries the window)
  - `npm_config_min_release_age="3"`
  - `pnpm_config_minimum_release_age="4320"` (minutes = 3 days)
  - `PIP_REQUIRE_VIRTUALENV=true` (refuses installs outside a venv)
- **Consequences:** Uniform, tool-agnostic delay. Cost: you are ~3 days behind
  newest releases by design (faster fix pickup than the prior 7-day window, less
  protection against a same-day malicious release). `NPM_CONFIG_FROZEN_LOCKFILE`
  and the uppercase `NPM_CONFIG_MIN_RELEASE_AGE` / `NPM_CONFIG_MINIMUM_RELEASE_AGE`
  / `PNPM_CONFIG_MINIMUM_RELEASE_AGE` duplicates are kept **commented** (they work
  but are heavy-handed/redundant — npm/pnpm read the lowercase vars
  case-insensitively).

## DR-006 | `NPM_CONFIG_IGNORE_SCRIPTS=true` | Accepted | 2025-12-02

- **Context:** `npm install` runs arbitrary `preinstall`/`postinstall` scripts —
  a common supply-chain attack vector.
- **Decision:** Disable lifecycle scripts globally via env var in
  `70_moratorium.sh`.
- **Consequences:** Strong supply-chain hardening. Cost: packages that *require*
  install scripts (e.g. some native builds) need an explicit opt-in.

## DR-007 | WSL2 login hardening: fstrim, shared root, cross-distro bind, keyring | Accepted (hardening, applied) | 2025-07-08

- **Context:** WSL2 (a) defaults `/` to *private* mount propagation (breaks
  rootless Podman), (b) stores the root filesystem on a grow-only VHDX (needs
  periodic `fstrim`), and (c) normally routes inter-distro file access through
  the Windows filesystem. `10_wsl2.sh` (guarded by `WSL_DISTRO_NAME`) fixes
  these on login.
- **Decision:** `10_wsl2.sh` applies, only while `WSL_DISTRO_NAME` is set:
  1. **Normalize `XDG_RUNTIME_DIR`** — strip a spurious trailing slash
     (`${XDG_RUNTIME_DIR%/}`). WSL2 reports it as `/run/user/1000/` (with the
     slash) versus `/run/user/1000` on real Linux; the extra `/` would otherwise
     double up in later path joins (e.g. the fstrim stamp path).
  2. **`sudo fstrim /`, once per session** — throttled by a stamp file
     (`$XDG_RUNTIME_DIR/.dotfiles-fstrim-$(id -u)`); runs at most once per WSL2
     session, not on every login (systemd timers already trim — this just tops
     it up). Skipped when the stamp already exists.
  3. **`sudo mount --make-shared /`** — only if `/` is currently `private`
     (`findmnt --noheadings -o PROPAGATION /`). Rootless Podman needs a *shared*
     root propagation mount to operate reliably; without it, image/container
     mounts fail or leak.
  4. **Cross-distro bind mount** — bind `/` to `/mnt/wsl/$WSL_DISTRO_NAME`
     (WSL2's shared `/mnt/wsl` namespace). This gives other WSL2 distros a
     direct path to this distro's filesystem so wsl2→wsl2 file operations don't
     have to round-trip through the Windows filesystem (DrvFS/9p).
  5. **`/usr/bin/gnome-keyring-daemon --start --components=secrets`** — a
     bootstrap hack to stand up a Secret Service (libsecret) provider in the
     environment, so apps expecting `org.freedesktop.Secret`/libsecret work
     without a full desktop session. Started only if `GNOME_KEYRING_CONTROL`
     is unset.
- **Consequences:** All fixes are idempotent and gated on `[ -n "$PS1" ]`
  (interactive shells only) since the **Applied (2026-07)** update; the `fstrim`
  throttle additionally makes it once-per-session. Caveats:
  - The owner runs WSL2 Fedora-44 as a **passwordless sudoer**, so the `sudo`
    prompts are a non-issue there (acknowledged 2026-07).
  - `fstrim` is still somewhat redundant with systemd timers.
  - On **Silverblue** / immutable hosts `sudo` + these mounts behave
    differently and may not persist as expected.

## DR-008 | Hardcoded OCI user OCID and Steam Deck volume UUID in tracked files | Accepted (risk accepted) | 2025-12-18

- **Context:** `60_containers.sh` points at a specific OCI config file; `80_path.sh`
  appends a specific Steam Deck mount path.
- **Decision (mistake, risk accepted):** Both paths are hardcoded with personal identifiers:
  - `ocid1.user.oc1..aaaaaaaaf3sb2fio74htiy5qs367vrcwl5fpxkwlw46r6xuurffdxfhoygba`
  - `/run/media/deck/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/…/bin`
- **Risk acceptance (2026-07):** The owner judges the OCID disclosure acceptable — an
  OCID alone cannot recover tenant data without Oracle "Insider" access or a
  government-grade judicial mandate, and both scenarios already imply broader PII
  exposure regardless of this file. The Steam Deck UUID is likewise a non-secret device
  identifier. Residual risk is accepted for a stable, explicit config path.
- **Status note (2026-09):** the OCI config block (OCID hardcode) is currently
  **commented out** in `60_containers.sh`; only the Steam Deck path in
  `80_path.sh` remains active.
- **Consequences:** Not a *secret* (OCIDs/UUIDs are identifiers, not
  credentials), but it is **PII** that uniquely fingerprints the owner's Oracle
  tenancy and a specific physical device, and it is brittle (breaks on any other
  machine). It remains brittle, so generalizing is still *technically* nicer, but it is
  **no longer flagged as a must-fix**. If portability ever matters, derive instead of hardcode:
  `default_oci="$(ls -1 "$HOME"/.oci/config.d/ocid1.user.*.config 2>/dev/null | head -n1)"`,
  and glob the Deck path: `"/run/media/deck"/*/var/home/deck/projects/bin`.

## DR-009 | `50_ip.sh` writes local IP addressing into a shared Android Documents folder | Accepted (risk accepted) | 2026-01-31

- **Context:** On Termux the LAN IP is dumped to
  `~/storage/shared/Documents/markor/ip.json` for an external app to read.
- **Consequences:** That folder is typically **synced/shared** (and world- or
  app-readable), so every interface/IP of every host you log into gets copied
  into a shared location.
- **Risk acceptance (2026-07):** On Android, any app holding the network/
  `INTERNET` permission can already read the device's own IP(s) directly via the
  OS networking APIs — the stale copy in a shared Documents folder adds no new
  capability an on-device app doesn't already have, and the data is local-only
  (LAN addresses, not credentials or remote identifiers). The disclosure surface
  is therefore effectively unchanged, so writing to the synced folder is
  **accepted** as low-risk. If it ever matters, writing to `$XDG_STATE_HOME`
  instead keeps the data off any synced/shareable location.

## DR-010 | Vendoring `bash-preexec.sh` (third-party, MIT) | Resolved (superseded — see DR-025) | 2025-04-22

- **Context:** Need zsh-like `preexec`/`precmd` hooks in bash for atuin.
- **Decision:** The upstream `bash-preexec` (rcaloras, MIT) is vendored
  wholesale and sourced by `70_history.bash` (interactive bash only).
- **Consequences:** Works, but it is 374 lines of foreign code committed to the
  repo. **Recommend:** track it as a git submodule or fetch on demand so updates
  are trivial and the diff stays clean.

## DR-011 | Replace imperative tool-config mutation with env-var config | Accepted | 2026-05-17

- **Context:** Earlier `deploy.sh` wrote tool state directly
  (`mise settings set …`, `npm config --global set …`, appended to `uv.toml`).
- **Decision:** Those settings moved into `70_moratorium.sh` as environment
  variables (`MISE_MINIMUM_RELEASE_AGE`, `NPM_CONFIG_*`, `UV_EXCLUDE_NEWER`,
  `PIP_*`, `PNPM_*`). `deploy.sh` no longer mutates other tools' config files.
- **Consequences:** Much safer — no clobbering of user/tool-owned config, and the
  policy travels with the shell, not with the install host. Good simplification.

## DR-012 | `VIRTUAL_ENV_DISABLE_PROMPT=1` | Accepted, not applied | 2025-12-02

- **Context:** Python venvs prepend `(venv)` to the prompt automatically.
- **Decision:** Disable that so the prompt stays under our control.
- **Status note (2026-09):** the variable is currently **commented out** in
  `70_moratorium.sh`, so venv prompts are shown by the tool. Re-enable there
  if the prompt should own it.
- **Consequences:** Cosmetic; fine if you render the venv yourself.

## DR-013 | Duplicate `profile.d/70_moratorium (1).sh` | Resolved (deleted) | 2025-06-06

- **Context:** A Windows-style "copy (1)" duplicate of `70_moratorium.sh` was
  present untracked in the tree.
- **Consequences:** The entrypoint glob (`profile.d/*`) **also sourced this
  file**, setting the moratorium env vars twice (idempotent, but clutter, and the
  space-in-filename is ugly/fragile for tooling).
- **Resolution (2026-07):** Deleted. The real `70_moratorium.sh` remains the only
  source.

## DR-014 | `80_path.sh` replaces `PATH` wholesale on non-cloud hosts | Accepted | 2025-04-23

- **Context:** Cloud shells (Google/AWS Cloudshell, Termux) pre-build a correct
  `PATH` we must not disturb ("don't mangle cursed $PATH").
- **Decision:** When *not* in a known cloud/termux environment, `PATH` is reset
  to a fixed, explicit list (`mise/shims` first, then `/usr/local/...`,
  `/usr/...`) plus a handful of optional dirs.
- **Consequences:** Predictable, minimal `PATH` on desktops/servers — but it
  **drops** entries added elsewhere (e.g. `/snap/bin`, `/usr/games`, distro
  additions, GUI session PATH). The stock per-user dirs (`~/.local/bin`,
  `~/bin`, `~/.bin`, `~/.shortcuts`) are deliberately never re-added — see
  DR-033. Usually fine for a dev CLI user; worth noting that it is a hard
  reset, not a merge.

## DR-015 | Single unified entrypoint `src-dotfiles.sh` | Accepted (applied) | 2026-07

- **Context:** The four shell rc files (`bash_profile.bash`, `bashrc.bash`,
  `zprofile.zsh`, `zshrc.zsh`) were byte-identical in pairs and only looped
  `profile.d/`. Maintaining four copies is needless duplication.
- **Decision (applied):** Replaced them with one POSIX entrypoint,
  `src-dotfiles.sh`, copied to all four rc targets by `deploy.sh`/`README`. It
  loops `profile.d/` and, under zsh, wraps each `*.sh` source in `emulate -L ksh`
  so POSIX snippets keep working while their exports still escape into the shell.
- **Consequences:** One source of truth for startup. The `*.sh`/`*.bash`/`*.zsh`
  split (DR-002) is unchanged. The entrypoint is dash-clean, so it can later be
  dropped into `/etc/profile.d` if native packaging is revisited. Because it is
  *copied* (not symlinked) to the home targets, each rc file stays self-contained.

---

## DR-016 | Allowlist atuin install locations in `70_history.{bash,zsh}` | Accepted (applied) | 2026-07

- **Context:** atuin's shell-history hook intermittently failed to activate on
  SSH logins — symptom was missing history, with `bash-preexec.sh` suspected.
  The old `70_history.bash` used a 3-way `if/elif` over hardcoded atuin paths
  (`/home/linuxbrew/.../atuin`, termux `atuin`, `/usr/bin/atuin`) and gated the
  whole block on `[ -n "$PS1" ]`. A debugging draft broadened discovery to a
  candidate list ending in `command -v atuin` (mise shim, cargo, `~/.local/bin`,
  …), but trusting an *arbitrary* atuin from `$PATH` is undesirable.
- **Decision:** Discover atuin from an **ordered allowlist** of known install
  locations — never an arbitrary `command -v atuin` from `$PATH`. First `-x`
  match wins, in this priority (mise shims preferred, brew next, termux/local last):
  1. mise shim under a custom `XDG_DATA_HOME` —
     `${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims/atuin`
  2. mise user shim (full-string default) — `~/.local/share/mise/shims/atuin`
  3. system mise shim — `${MISE_SYSTEM_DATA_DIR:-/usr/local/share/mise}/shims/atuin` (env-var form)
  4. system mise shim (full-string default) — `/usr/local/share/mise/shims/atuin`
  5. brew — `/home/linuxbrew/.linuxbrew/bin/atuin`
  6. termux — `/data/data/com.termux/files/usr/bin/atuin` (**fallback**)
  7. local/system — `/usr/bin/atuin` (**fallback**)
  For discoverability the literal default paths are listed alongside their
  `XDG_DATA_HOME`/`MISE_SYSTEM_DATA_DIR` env-var forms (the mise user shim at
  `~/.local/share/mise/shims/atuin` is also the `XDG_DATA_HOME` default, and
  `/usr/local/share/mise/shims/atuin` is the `MISE_SYSTEM_DATA_DIR` default), so
  the default install locations are always searched even when those vars point
  elsewhere. Termux and the local/system atuin are deliberately last (fallback
  only). Each candidate is additionally validated by running `<cand> --version`
  (must exit 0); a mise shim that exists but has no version selected (`mise
  ERROR No version is set for shim: atuin`, exit 1) is auto-provisioned once via
  `mise use -g atuin` and then re-checked before it is trusted.
  Structural fixes retained: **always** run `atuin init bash` when found, source
  `bash-preexec.sh` **before** `atuin init` and treat a missing file as non-fatal
  (`[ -r … ]` guard — modern atuin bundles bash-preexec itself and auto-loads
  it when none is present, DR-025), and detect
  interactivity with `case "$-" in *i*)` instead of `$PS1`. The same
  allowlist/discovery mechanism is mirrored in `70_history.zsh` (using
  `atuin init zsh`); zsh has native `preexec`/`precmd` hooks, so the
  `bash-preexec.sh` step is omitted there.
- **Consequences:** atuin initializes wherever it is installed via brew, mise
  (user/system/XDG shim), the system package manager (`/usr/bin/atuin`), or
  Termux — in that priority. The old `/usr/bin/atuin` branch bug (it sourced
  `bash-preexec.sh` but never ran `atuin init bash`) is gone. An atuin that is
  only on `$PATH` but not at an allowlisted path is intentionally ignored (avoids
  trusting an arbitrary binary). A missing/absent `bash-preexec.sh` no longer
  breaks atuin initialization. A mise shim that exists but has no version
  selected is auto-provisioned with `mise use -g atuin` rather than silently
  skipped. `deploy.sh` was **intentionally left unchanged**:
  it only copies `src-dotfiles.sh`, and extending it to also deploy `profile.d/`
  and `bash-preexec.sh` would risk leaving stale copies of both lying around on
  previously-provisioned hosts; the full repo checkout remains the supported
  deployment path.

## DR-017 | Canonical interactive guard (`$-`) for shell-specific snippets | Accepted (applied) | 2026-07

- **Context:** Shell-specific snippets (atuin in `70_history.{bash,zsh}`, keybinds
  in `90_navigation.zsh`) must only run in interactive shells. The atuin snippets
  already used the canonical `case "$-" in *i*)` test; `90_navigation.zsh`
  instead gated on `[ -n "$PS1" ]` (a weaker proxy).
- **Decision:** Rewrite `90_navigation.zsh` to use the same pattern as the atuin
  snippets — `if [ -n "$ZSH_VERSION" ]; then case "$-" in *i*)`, keeping its
  existing `TERM = xterm-256color` restriction (the keybinds are only meaningful
  on that terminal type).
- **Consequences:** All shell-specific snippets now use one uniform, robust
  interactivity test (`$-` contains `i`), so none fire in non-interactive sessions
  (`ssh host command`, `scp`, CI). The `TERM` filter on the navigation binds is
  retained.
- **Status note (2026-09):** applied to `40_completion.{bash,zsh}` as well
  (they still gated on `$PS1`); `90_navigation.zsh` also got its shell
  exclusivity `else` split from the TERM check — under zsh with a non-xterm
  TERM it must not print the wrong-shell warning (DR-034).


## DR-018 | Defense-in-depth for shell-exclusive snippets | Accepted (applied) | 2026-07

- **Context:** `profile.d/` mixes POSIX `.sh` snippets (sourced by every shell)
  with shell-exclusive `.bash` and `.zsh` snippets. A `.bash` file must never
  run under zsh (and vice-versa): its body uses bashisms/zshisms (`source <(…)`,
  `compinit`, `bindkey`, `atuin init bash/zsh`, …) that error or misbehave in the
  wrong interpreter.
- **Decision:** Enforce shell exclusivity in **two layers**, plus a warning:
  1. **Entrypoint extension filter** — `src-dotfiles.sh` only sources `.bash`
     files when `BASH_VERSION` is set and `.zsh` files when `ZSH_VERSION` is set,
     so a shell-exclusive file is never even *read* by the wrong shell.
  2. **Per-file shell guard** — every `.bash` file wraps its body in
     `if [ -n "$BASH_VERSION" ]; then …`, and every `.zsh` file in
     `if [ -n "$ZSH_VERSION" ]; then …`, as a second, independent check.
  3. **Wrong-shell warning** — each shell-exclusive file adds an `else` branch
     that does `printf '%s\n' "dotfiles: <shell>-only snippet sourced under a
     non-<shell> shell; skipping" >&2`, surfacing accidental wrong-shell
     sourcing on stderr instead of failing silently.
- **Consequences:** Three independent safeguards; the body executes only when
  both the entrypoint and the file's own guard agree the shell is correct, and
  any violation is reported on stderr. `.sh` files are intentionally exempt
  (they are POSIX and must run everywhere). The per-file guard and warning
  remain correct even if `src-dotfiles.sh`'s filtering changes or the file is
  sourced manually — true defense-in-depth.

## DR-019 | Unset internal/temporary variables to avoid leaking into the shell | Accepted (applied) | 2026-07

- **Context:** Several `profile.d` snippets assign helper variables while
  running (loop counters, discovered binary paths, function parameters — which
  are global in POSIX `sh`/`dash` — `mise use` attempt flags, …). Sourced at
  login, these would otherwise persist in the interactive shell environment.
- **Decision:** Every snippet `unset`s its internal temporaries before leaving
  its scope: `cand`/`mise_attempted`/`atuin_bin` in the atuin loops
  (`70_history.{bash,zsh}`), `default`/`target` and the `merge_history` function
  in `70_history.sh`, `gnome_env` in `10_wsl2.sh`, `dir` in `80_path.sh`,
  `default_oci` in `60_containers.sh`, `bash_completion` in `40_completion.bash`,
  and `rc`/`_src_one` in `src-dotfiles.sh`. Intentional environment exports
  (`PATH`, `*_HISTORY`, `OCI_*`, `KUBECONFIG`, `NPM_CONFIG_*`, `PIP_*`, `UV_*`,
  `MISE_*`, `GNOME_KEYRING_CONTROL`, `ANDROID_HOME`, …) are deliberately left
  set.
- **Consequences:** No internal scratch variable leaks into the interactive
  shell. The cleanup is idempotent and cheap, and does not affect the exported
  configuration the snippets exist to establish.

## DR-020 | Source distro/system bashrc in `20_core.bash` | Accepted | 2026-07

- **Context:** Our dotfiles own the rc flow (DR-004/DR-015), replacing the
  stock `~/.bashrc`, which on most distros sources `/etc/bashrc` (and distro
  completion/`profile.d`) and cloud shells inject their own rc. Without
  re-sourcing those, distro-provided setup (prompt, completions, PATH extensions,
  cloud-shell hooks) would be silently lost.
- **Decision:** `20_core.bash` (guarded on `BASH_VERSION`, DR-018) sources the
  relevant system-wide rc files when readable:
  - `/etc/bashrc` (Fedora/RHEL and friends),
  - Termux's `$PREFIX/etc/bash.bashrc`,
  - Google Cloud Shell's `/google/devshell/bashrc.google`,
  - Oracle Cloud Shell's `/etc/bashrc.cloudshell`.
  Each is `-r`-guarded so absent files are skipped.
- **Consequences:** Distro and cloud-shell environment setup is inherited even
  though the dotfiles supply the rc. Safe and idempotent; no-op on systems
  lacking those files. The file is bash-only, so the body never runs under zsh
  (DR-018).

## DR-021 | Programmable completion setup in `40_completion.{bash,zsh}` | Accepted | 2026-07

- **Context:** Interactive shells want tab-completion for the CLI tools in use
  (kubectl, mise, uv/uvx, brew). Each tool ships its own completion
  script, but since the dotfiles own the rc flow these must be wired up
  explicitly. (atuin's advanced command-history management is the related
  facility but lives in `70_history.{bash,zsh}` — see DR-016.)
- **Decision:** `40_completion.bash`/`40_completion.zsh` (guarded on
  `BASH_VERSION`/`ZSH_VERSION`, interactive-only, DR-017/DR-018) discover each
  tool via an allowlist cascade and wire up its completion:
  - **Cascade order** (mirrors DR-016's atuin allowlist — no arbitrary `$PATH`):
    per tool, `mise` user shim -> system `mise` shim (`MISE_SYSTEM_DATA_DIR` /
    `/usr/local/share/mise`) -> `brew` -> system (`/usr/bin`); `mise` itself
    uses the shorter `brew` -> system cascade.
  - `brew shellenv` (bash/zsh) puts brew's completions on `PATH`.
  - the bash-completion framework (`/etc/profile.d/bash_completion.sh` and
    linuxbrew's `bash_completion.sh`, else sourcing linuxbrew's
    `bash_completion.d/*`).
  - `mise activate bash/zsh`, `uv`/`uvx` shell-completion (bash/zsh) via
    the discovered binaries.
  - kubectl completion via `source <(kubectl completion bash/zsh)` (process
    substitution — the reason this file is shell-specific, DR-002).
- **Consequences:** Tab-completion works for those tools in interactive bash and
  zsh. The `source <(…)` step is a bashism/zshism, so this stays in `.bash`/`.zsh`
  rather than `.sh`; it is interactive-gated and defended by DR-018. atuin
  history (search/stats/sync) is configured separately under DR-016.

## Cross-cutting note for packaging (feeds DR-001/DR-002)

`/etc/profile` on Debian/Fedora loops `/etc/profile.d/*.sh` **under dash**, and
only for **login** shells. Critically, **Debian's `/etc/zsh/zprofile` does NOT
source `/etc/profile`** (Fedora/Silverblue's does). So a pure `/etc/profile.d`
drop-in covers bash/ksh login everywhere and zsh login on Fedora, but **not zsh
on Debian**, and **never non-login interactive shells**. Any packaging plan must
therefore still install per-user entrypoints (`~/.bashrc`, `~/.zshrc`, …) —
`/etc/profile.d` is a bonus for login shells, not a complete replacement.

## DR-022 | Git Bash / MSYS2 (Win32) coverage: `.exe` shims, Windows-owned PATH | Accepted (applied) | 2026-07

> Part 1 (`.exe` fallback) superseded by DR-028 — the fallback was simplified
> to embedding the `.exe` spelling in the Windows-only candidates.

- **Context:** The dotfiles now run in Git Bash / MSYS2 bash on Win32, with
  scoop as the userland package manager. Two Windows facts break the naive
  port: (1) scoop shims are PE binaries — `~/scoop/shims/atuin.exe` exists but
  `~/scoop/shims/atuin` does not, so the allowlists' `[ -x ]` probes silently
  miss atuin, uv, kubectl, mise, …; (2) PATH is owned by Windows (System32,
  per-user dirs, scoop), so the DR-014 wholesale reset would make native
  executables unreachable. Three more differences matter: native tools read
  `;`-separated lists (kubectl's `KUBECONFIG`) not `:`, msys2/Git Bash ship
  their system bashrc as `/etc/bash.bashrc` (not Fedora's `/etc/bashrc`), and
  there is usually no zsh, so the `.zshrc`/`.zprofile` deploy targets would
  litter the Windows profile.
- **Decision:**
  1. **`.exe` fallback everywhere** — the atuin allowlist
     (`70_history.{bash,zsh}`) and the completion cascade (`40_completion.bash`)
     first probe the candidate, then `$cand.exe` (a no-op on POSIX where no
     such files exist); the mise-shim auto-provision pattern became
     `*/mise/shims/atuin*` so a normalized `atuin.exe` still matches. Scoop's
     shim dir (`"${SCOOP:-$HOME/scoop}/shims"`) and mise's Windows data dir
     (`"${LOCALAPPDATA:-$HOME/AppData/Local}/mise"` — `shims/` for per-tool
     shims, `bin/mise.exe` for the standalone binary) join each cascade.
  2. **PATH ownership** — `80_path.sh` detects Win32 (`uname -s` →
     `*MINGW*|*MSYS*|*CYGWIN*`) and never resets PATH; it only appends
     `${SCOOP:-$HOME/scoop}/shims` when missing and exports `SCOOP`.
  3. **System bashrc** — `20_core.bash` also sources `/etc/bash.bashrc`
     (msys2 / Git Bash; on Debian/Ubuntu this closes the DR-020 gap where the
     distro bashrc was never sourced because the dotfiles own `~/.bashrc`).
  4. **KUBECONFIG separator** — `60_containers.sh` joins config paths with
     `;` on Win32 (kubectl.exe is a native binary).
  5. **deploy** — `deploy.sh` writes the zsh entrypoints only when
     `command -v zsh` succeeds and uses `$HOME` expansions instead of `~`.
- **Consequences:** The same `profile.d/` flow runs unmodified in Git Bash:
  scoop-installed tools are discovered and their completions/atuin hook wired
  up, Windows PATH (and thus native executables) survives, and no stray zsh
  files appear in `%USERPROFILE%`. Cost: a few extra `uname -s` calls per
  snippet and one extra `-x` stat per candidate on every platform (cheap).
  Windows-specific branches are all `case`/`-d`/`-r`-guarded and inert on
  POSIX. Caveat: if `SCOOP` or `LOCALAPPDATA` is exported in Windows style
  (`C:\...`), the `-x` probes assume msys path conversion; leaving them
  unset (the default) avoids that entirely.

## DR-023 | Win32 artifact resolution: mise's Windows data dir (`%LOCALAPPDATA%\mise`) | Accepted (applied) | 2026-07

- **Context:** Scoop shims only cover scoop-installed apps. Tools installed via
  mise (`mise use -g atuin`) get their shims in mise's own data dir, which on
  Windows is `%LOCALAPPDATA%\mise\shims` — mise does not use the Unix
  `~/.local/share/mise` default there, so the allowlists' XDG/`$HOME` mise
  candidates could never match a mise-managed tool under Git Bash. Separately,
  a standalone (non-scoop) Windows mise install places the binary itself at
  `%LOCALAPPDATA%\mise\bin\mise.exe`.
- **Decision:**
  1. **`LOCALAPPDATA` joins each cascade** — the atuin allowlist
     (`70_history.{bash,zsh}`) and `_dotfiles_tool` (`40_completion.bash`)
     gain `"${LOCALAPPDATA:-$HOME/AppData/Local}/mise/shims/<tool>"`; `_dotfiles_mise`
     gains `"${LOCALAPPDATA:-$HOME/AppData/Local}/mise/bin/mise"` for the
     standalone binary. Entries sit with the other per-user data-dir
     candidates; the `.exe` fallback (DR-022.1) resolves the PE spelling.
  2. **Auto-provision pattern still matches** — the mise-shim `case` pattern
     (`*/mise/shims/atuin*`) matches the new candidate unchanged, since `*`
     crosses the backslashes of a Windows-style `$LOCALAPPDATA`.
- **Consequences:** Mise-managed tools resolve and wire up (atuin hook,
  completions, `mise activate`) under Git Bash even with no scoop install of
  the tool; the standalone mise binary's shell hook works. On POSIX the
  candidates resolve to `$HOME/AppData/Local/...`, which does not exist, so
  they are inert (same cost model as DR-022). Caveat (shared with DR-022): if
  `LOCALAPPDATA`/`SCOOP` are exported Windows-style (`C:\...`), the `-x` probes
  rely on msys path conversion; leaving them unset gives POSIX paths
  (`$HOME/AppData/Local`).

## DR-024 | XDG_* vars stay at Unix-y defaults on Win32 (no remap) | Accepted (applied) | 2026-07

- **Context:** Windows keeps per-user data dirs in `%LOCALAPPDATA%`/`%APPDATA%`,
  and tools like mise use those instead of `XDG_DATA_HOME`. Remapping `XDG_*`
  to Windows dirs in `profile.d/` was tempting for "native" behavior.
- **Decision:** Leave `XDG_*` unset/unmodified on Windows — they keep their
  Unix-y defaults (`~/.local/...`). Platform-specific dirs are probed directly
  where they matter: `${LOCALAPPDATA:-$HOME/AppData/Local}/mise/...` in the
  cascades (DR-023) and `${SCOOP:-$HOME/scoop}/shims` for scoop (DR-022). No
  Windows-specific XDG assignment is emitted anywhere.
- **Consequences:** One set of XDG defaults across platforms, so behavior is
  predictable and diff-free vs. POSIX. Cost: msys programs that genuinely read
  `XDG_*` (rare — most use `LOCALAPPDATA`) will not find Windows-style paths;
## DR-025 | bash-preexec: superseded by atuin's bundled copy (≥ 18.18.x) | Accepted (applied) | 2026-07

- **Context:** DR-010 vendored rcaloras' `bash-preexec.sh` (374 lines) at the
  repo root, sourced by `70_history.bash` before `atuin init`, because atuin's
  bash integration hooks `preexec_functions`/`precmd_functions` and
  historically required an external bash-preexec or ble.sh. Verification
  against the atuin source (`/references/github/atuinsh/atuin`) shows that is
  no longer true for current atuin.
- **Evidence (atuin source):**
  - `crates/atuin/src/shell.rs` — `BASH.preexec` embeds the vendored
    `vendor/bash-preexec/bash-preexec.sh` (566 lines) into the binary.
  - `crates/atuin/src/command/client/init/bash.rs` — `atuin init bash` emits
    `__atuin_load_builtin_preexec() { … }` containing that whole script, unless
    `ATUIN_NO_BUILTIN_PREEXEC` is set.
  - `crates/atuin/src/shell/atuin.bash` (end of script) — if no other preexec
    backend is detected (`BLE_ATTACHED`, `bash_preexec_imported`,
    `__bp_imported`), it calls `__atuin_load_builtin_preexec` to install the
    hooks, then unsets the function.
  - Landed in commit f1ed2e0be "feat(bash): bundle bash-preexec with Atuin;
    automatically load if no other preexec backend is loaded (#3650)",
    2026-07-16; present in the 18.18.x line (HEAD v18.18.0-beta.2-36,
    Cargo.toml 18.18.0-beta.3).
  - atuin's `install.sh` also has a legacy bash path that downloads
    `~/.bash-preexec.sh` and sources it — for older atuin.
- **Decision:** For atuin ≥ 18.18.x the dotfiles' vendored `bash-preexec.sh` is
  redundant: atuin preloads its own bundled copy automatically, and if the
  dotfiles load the external copy first atuin detects it and skips its builtin
  (identical behavior either way). Keep the vendored copy as the fallback for
  atuin < 18.18.x (which still requires an external bash-preexec or ble.sh).
  The `70_history.bash` comment was corrected — the modern fallback is the
  bundled bash-preexec, not PROMPT_COMMAND. DR-010 is thereby resolved as
  superseded.
- **Consequences:** No behavior change on current atuin; old-atuin users keep
  working via the vendored copy. If/when the atuin floor moves to ≥ 18.18.x,
  delete `bash-preexec.sh` and the sourcing block and flip DR-010 to
  "Resolved (deleted)". The frozen-snapshot concern in DR-010 is moot — the
  bundled copy tracks atuin releases.

## DR-026 | Mise-shim probes are gated on `command -v mise` | Accepted (applied) | 2026-07

- **Context:** `$LOCALAPPDATA/mise/shims/*.exe` (and the POSIX shim dirs) are
  runtime shims: they only work while the `mise` binary itself is resolvable
  from `$PATH` (scoop-installed mise → `~/scoop/shims/mise.exe`; standalone →
  a user-added dir). If mise isn't reachable — e.g. a fresh install where the
  inherited Windows PATH predates scoop — the shim files still exist and pass
  `-x`, so probes that trust `-x` alone would select a shim that fails when
  executed, and it shadows later candidates.
- **Decision:** In `_dotfiles_tool` (`40_completion.bash`), candidates under
  `*/mise/shims/*` are only trusted when `command -v mise` succeeds; otherwise
  the cascade continues. The atuin loop (`70_history.{bash,zsh}`) already had
  this property via its `--version` runtime verification (and its auto-provision
  branch explicitly requires `command -v mise`). `_dotfiles_mise` is untouched —
  it probes the mise binary itself (standalone `bin/mise.exe` or the scoop
  shim), which needs no mise on PATH.
- **Consequences:** A mise shim is never selected (or executed) while its mise
  binary is unreachable; the cascade falls through to scoop/system candidates.
  POSIX behavior unchanged (mise is on PATH whenever its shims exist and work).
  The pre-existing POSIX PATH reset in `80_path.sh` still prepends mise shim
  dirs unconditionally — harmless there since the dirs only exist after mise has
  run; a stale-shims-after-uninstall case would be caught by the same probes
  skipping them.
- **Status note (2026-09, DR-034):** the "mise is on PATH whenever its shims
  exist" assumption does not hold at 40/70 snippet time — snippets run before
  `80_path.sh`, so a fresh login with a script-installed mise (no brew/system
  mise on PATH) failed the `command -v mise` gate and skipped all mise-shim
  completions. The gate now also accepts a mise binary found by the
  allowlisted `_dotfiles_mise` probe (which gained the standalone POSIX
  locations `~/.local/bin/mise` and `$XDG_DATA_HOME/mise/bin/mise`).

## DR-028 | Win32 `.exe` spelling embedded in Windows-only candidates | Accepted (applied) | 2026-07

- **Context:** DR-022.1's `.exe` fallback probed every candidate twice
  (`[ -x "$cand" ]` then `[ -x "$cand.exe" ]`) in the atuin allowlist
  (`70_history.{bash,zsh}`) and the completion cascade
  (`40_completion.bash`). Most platforms are not Git Bash, so each probe
  paid an extra `-x` stat per candidate for a fallback that only ever fires
  on Win32 — and only for the Windows-only path prefixes.
- **Decision:** Drop the fallback branches entirely. The Windows-only
  candidates now embed the `.exe` spelling directly in the candidate list:
  `"${LOCALAPPDATA:-$HOME/AppData/Local}/mise/shims/<tool>.exe"`,
  `"${LOCALAPPDATA:-$HOME/AppData/Local}/mise/bin/mise.exe"`, and
  `"${SCOOP:-$HOME/scoop}/shims/<tool>.exe"`. All POSIX candidates
  (`$XDG_DATA_HOME`/`$HOME/.local`/`MISE_SYSTEM_DATA_DIR`/linuxbrew/`/usr/bin`)
  stay extensionless. Every probe is again a single `[ -x ]` (DR-016's
  allowlist shape).
- **Consequences:** On POSIX nothing changes — the Windows-only paths are
  inert, `.exe`-suffixed or not. On Win32, mise and scoop shims are PE
  binaries (`atuin.exe`, `mise.exe`, …) so the `.exe` spelling is the only
  correct one; there is no extensionless twin that the old fallback could
  have found that the new spelling misses. Case patterns keyed on the
  `*/mise/shims/*` shape (the DR-026 gate in `_dotfiles_tool`, the
  auto-provision branch in `70_history`) match both `atuin` and `atuin.exe`,
  so they are unaffected. Removes one `-x` stat per candidate per shell on
  every platform (DR-022's documented cost).

## DR-027 | Termux startup chain: idempotency guard in src-dotfiles.sh | Accepted (applied) | 2026-07

- **Context:** On Termux, `bash --login` reads `$PREFIX/etc/profile`, which
  sources `~/.bashrc` when the shell is interactive and not in posix/sh mode.
  The dotfiles flow then re-enters the chain twice: `20_core.bash` sources that
  same profile (to get Termux env in non-login shells), and the profile sources
  `~/.bashrc` again → unbounded recursion; separately, bash (login) also reads
  `~/.bash_profile` after `/etc/profile` → every snippet would run twice.
- **Decision:** Add an idempotency guard at the top of `src-dotfiles.sh` —
  `DOTFILES_SOURCED=1` after an early `return` on re-entry (POSIX; works when
  sourced by bash/dash/zsh, `|| exit 0` covers accidental direct execution).
  The variable is deliberately not unset so it survives across the rc files
  sourced in one shell process. Keep deploying `~/.bash_profile` on Termux: it
  is the only entrypoint for non-interactive login shells (ssh 'cmd'), and the
  guard makes the login double-read a no-op. `20_core.bash` keeps sourcing
  `$PREFIX/etc/profile` — with the guard, the profile's own re-entry into
  `~/.bashrc` stops at the first hop.
- **Consequences:** No behavior change elsewhere — login shells read exactly
  one of `.bash_profile`/`.bashrc` on normal platforms, so the guard never
  fires there. A manual `source ~/.bashrc` in an already-loaded shell is now a
  no-op until `unset DOTFILES_SOURCED`. Recursion is broken at the first
  re-entry hop, so snippet side effects (PATH, eval'd `atuin init`, …) happen
  exactly once per shell.

## DR-029 | Win32 PATH gains mise's Windows dirs (bin + shims) | Accepted (applied) | 2026-07

- **Context:** The `80_path.sh` Win32 branch appended only scoop's shim dir
  (DR-022.2), on the theory that Windows PATH is owned by Windows. But mise on
  Windows installs into `%LOCALAPPDATA%\mise` and does not reliably put its
  own dirs on PATH in a Git Bash/MSYS2 inherited environment, so `mise` itself
  and its per-tool shims could be unreachable from Git Bash.
- **Decision:** Extend the append-only block (still never a reset) to also add
  `${LOCALAPPDATA:-$HOME/AppData/Local}/mise/bin` (the `mise` binary) and
  `${LOCALAPPDATA:-$HOME/AppData/Local}/mise/shims` (per-tool shims) when they
  exist, each gated on `[ -d ]` and on not already being in PATH. Same shape
  as the existing scoop block; the fallback `$HOME/AppData/Local` covers an
  unset `LOCALAPPDATA`.
- **Consequences:** `mise`, `mise use`, and tools with mise shims become
  callable from Git Bash without manual PATH edits. The invariant holds: the
  Windows-owned PATH is only ever appended to, and only with existing dirs, so
  nothing becomes unreachable. Mirrors the POSIX branch's mise-shims-on-PATH
  behavior (DR-014) without its wholesale reset.

## DR-030 | PowerShell entrypoint: src-dotfiles.ps1 + profile.d/*.ps1 | Accepted (applied) | 2026-07

- **Context:** The bash/zsh flows cover Git Bash, MSYS2 and Termux, but a
  native PowerShell session (5.1 "Windows PowerShell" or 7.x Core) has no
  dotfiles entrypoint at all. The profile.d snippets are POSIX/bash/zsh and
  cannot be sourced by PowerShell.
- **Decision:** Add `src-dotfiles.ps1`, a PowerShell analog of
  `src-dotfiles.sh`: the same `DOTFILES_SOURCED` idempotency guard (kept as a
  session-local `$global:` variable, deliberately not an env var — same
  process-locality semantics as the bash guard), the same `$DOTFILES`-or-script-
  dir root resolution, and the same sorted `profile.d/` loop — but it only
  sources `*.ps1` snippets. Compatible with 5.1 and 7.x: no 7-only syntax,
  `$PSScriptRoot` (3.0+), `$env:OS -eq 'Windows_NT'` for the Windows gate, and
  `return`-based guard (valid when dot-sourced or invoked). The single snippet
  so far is `profile.d/70_history.ps1`, roughly
  `atuin init powershell | Out-String | Invoke-Expression`: atuin is resolved
  from the allowlisted Windows locations (`%LOCALAPPDATA%\mise\shims`,
  `$USERPROFILE\.local\share\mise\shims`, scoop shims — `.exe` spelling
  embedded per DR-028), smoke-tested with `--version` (DR-016), and only then
  is its init blob evaluated, in a `try/catch` so a PSReadLine-less host does
  not break the session. No PATH changes are made from the entrypoint or the
  snippet — that stays in `80_path.sh` for the bash flow.
- **Consequences:** PowerShell sessions get the atuin history hook; the
  infrastructure is in place for further `*.ps1` snippets (the 10_..90_ prefix
  order applies). Wire-up is one line in `$PROFILE` (documented in README).
  Cost: `src-dotfiles.ps1` runs `Get-ChildItem` once per session (cheap; no
  snippets yet means an empty loop). Not verified against a real 5.1 host in
  CI — compatibility is by construction (feature set used is 3.0+).

## DR-031 | PowerShell kubectl completion: profile.d/40_completion.ps1 | Accepted (applied) | 2026-07

- **Context:** The PowerShell flow (DR-030) shipped with only the atuin hook.
  kubectl needs the same treatment on native PowerShell: roughly
  `kubectl completion powershell | Out-String | Invoke-Expression`, and the
  kubectl branch of `_dotfiles_tool` in `40_completion.{bash,zsh}` is the
  POSIX precedent.
- **Decision:** Add `profile.d/40_completion.ps1`, mirroring `70_history.ps1`
  rather than the bash completion function: kubectl is resolved from the same
  ordered allowlist of Windows locations (`%LOCALAPPDATA%\mise\shims`,
  `$USERPROFILE\.local\share\mise\shims`, scoop shims — `.exe` spelling
  embedded per DR-028), each candidate smoke-tested with `--version` (a mise
  shim with no version selected fails this, so the DR-026 gate is subsumed),
  and the `completion powershell` blob is evaluated in a `try/catch` so a
  PSReadLine-less host does not break the session. Windows-gated
  (`$env:OS -eq 'Windows_NT'`) like `70_history.ps1`.
- **Consequences:** kubectl tab-completion works in native PowerShell for
  scoop- and mise-managed installs, without trusting an arbitrary `kubectl`
  from `$PATH` (winget/choco installs are out of scope — add a candidate if
  you use one). The bash/zsh sides are unchanged.

## DR-033 | Stock per-user extension points intentionally not honored (`~/.bashrc.d`, `~/.local/bin`, `~/bin`, `~/.bin`, `~/.shortcuts`) | Accepted (applied) | 2026-08

- **Context:** `deploy.sh` copies `src-dotfiles.sh` over the skel
  `~/.bashrc` (and the other three rc targets). The Fedora-family skel
  `.bashrc` (verified against the Bazzite dump) then does two things the
  dotfiles never do: it sources `~/.bashrc.d/*` as a per-user extension
  point, and it prepends `$HOME/.local/bin` + `$HOME/bin` to PATH. Termux
  setups commonly extend the same idea with `~/.bin`; `~/.shortcuts` and
  `~/.shortcuts/tasks` are Termux:Widget's script dirs (foreground
  shortcuts / background tasks — see `docs/requirements.md` §2.1 and
  `docs/system.md` §3) and are
  likewise never on PATH.
- **Decision:** Both are intentionally dropped, not oversights. The single
  supported extension point is `~/dotfiles/profile.d/` — every `*.sh`,
  `*.bash`, `*.zsh` and `*.ps1` snippet there is sourced by every shell
  behind the DR-027 guard, regardless of distro. Honoring `~/.bashrc.d` in
  addition would create a second, distro-specific extension mechanism that
  only some platforms have; anything that would have lived in `~/.bashrc.d`
  belongs in `profile.d/` instead. Likewise `80_path.sh`'s DR-014 reset
  deliberately keeps `~/.local/bin`, `~/bin`, `~/.bin`, `~/.shortcuts` (and
  installer dirs like `.dotnet/tools`) out of its candidate list — see the
  commented-out entries in `80_path.sh`. Tools that drop binaries into
  `~/.local/bin` are still reachable at their own level: the atuin
  allowlist probes known install locations (mise shims, brew, Termux,
  `/usr/bin`), never the bare `~/.local/bin` dir.
- **Consequences:** On the first deploy, skel snippets that relied on
  `~/.bashrc.d` stop loading (their effects vanish until migrated into
  `profile.d/`), and the skel's PATH entries are gone on DR-014 hosts
  (Silverblue, WSL2, Debian, …). On Termux and cloud shells the reset is
  skipped, so nothing is dropped there. This is a deliberate trade for one
  predictable extension point and one predictable PATH.

## DR-032 | Dynamic KUBECONFIG in PowerShell: profile.d/60_containers.ps1 | Accepted (applied) | 2026-07

- **Context:** `60_containers.sh` builds KUBECONFIG from
  `$HOME/.kube/config.d` and already handles the Win32 list separator (`;`
  for native kubectl.exe, `:` elsewhere). Native PowerShell had no equivalent.
- **Decision:** Add `profile.d/60_containers.ps1` with the same rule: if
  `$HOME\.kube\config.d` exists (container check), `$env:KUBECONFIG` is the
  list of its files joined by `;` on Windows_NT, `:` otherwise; never unset or
  clobbered when the directory is missing. Two deliberate deltas from the sh
  version, documented in the file: the list is `Sort-Object Name`-sorted
  (deterministic, unlike `find`'s directory-entry order) and has no trailing
  separator (kubectl treats empty entries as "no file" either way — the sh
  version's trailing separator is harmless but noisy). `$HOME` (the automatic
  variable) is used instead of `$env:USERPROFILE` so the snippet is
  cross-platform like its sh counterpart.
- **Consequences:** Git Bash and native PowerShell produce the same KUBECONFIG
  set from the same config.d; order is now deterministic on both flows
  (sh side remains as-is). No other behavior change.

## DR-034 | Consistency fix batch: history leak, completion gating, lint, PS hygiene | Accepted (applied) | 2026-09-17

- **Context:** An audit found (a) `merge_history` echoed legacy history files
  to the terminal at login (`tee` mirrors stdin to stdout), (b) the
  bash-completion framework was probed with `-x` although it is *sourced* —
  distro packages install `/etc/profile.d/bash_completion.sh` 0644, so it
  never loaded on Silverblue/Bazzite, (c) `90_navigation.zsh` printed the
  wrong-shell warning under zsh whenever TERM was not xterm-256color, (d)
  `lint.sh` globbed `*sh`, so shellcheck errored (SC1071) on every `.zsh`
  file and lint could never pass, (e) `60_containers.{sh,ps1}` clobbered an
  inherited `KUBECONFIG` with an empty string when `~/.kube/config.d` existed
  but was empty, and (f) `50_ip.sh` ran on every non-interactive shell
  (`ssh host cmd`), writing to shared storage.
- **Decision:**
  1. `merge_history` uses `tee -a -- "$target" >/dev/null`.
  2. Framework probe is `-r` (the adjacent linuxbrew check already was).
  3. The shell-exclusivity `else` in `90_navigation.zsh` is separated from
     the TERM check; a non-xterm TERM under zsh is a silent no-op.
  4. `lint.sh` checks only `*.sh`/`*.bash` with shfmt/shellcheck, runs
     `zsh -n` over `*.zsh`, truncates `report.txt` per run, uses portable
     `date +%F`, and propagates tool failures as its exit status. Default
     `*) : ;;` cases were added where shellcheck wanted them (SC2249).
  5. `KUBECONFIG` is only set when the config.d listing is non-empty.
  6. `50_ip.sh` is interactive-only (`case "$-" in *i*)`).
  7. PowerShell scratch variables are removed after use
     (`src-dotfiles.ps1`, `40_completion.ps1`, `70_history.ps1`,
     `60_containers.ps1`) — extending DR-019's hygiene to the PowerShell
     flow.
  8. `40_completion.bash` and `40_completion.zsh` moved to the canonical
     `case "$-" in *i*)` guard (completing DR-017), and the mise-shim trust
     gate now also accepts a mise binary found by `_dotfiles_mise`, which
     gained the standalone POSIX locations (`~/.local/bin/mise`,
     `$XDG_DATA_HOME/mise/bin/mise`) — fixing the DR-026 first-login gap.
- **Consequences:** First-login completion discovery works for
  script-installed mise; no history dump, no false warnings, no empty
  KUBECONFIG clobber; lint is deterministic and able to pass (exit 0).
  Costs: `50_ip.sh` no longer refreshes `ip.json` from non-interactive
  shells (acceptable — the consumer reads it from interactive sessions);
  the KUBECONFIG no-trailing-separator/sorted-sh side now matches DR-032's
  documented PowerShell behavior more closely, except the sh side keeps its
  unsorted `find` order.

## DR-035 | Documentation set: BRD / SRD / TDD plus the decision log | Accepted (applied) | 2026-09-17

- **Context:** `README.md` had grown into a monolith mixing three document
  types: requirements material (scope, supported environments, accepted
  limitations and risks), systems-reference material (startup chains,
  component inventory, runtime behavior) and design material (mechanisms,
  install/lint procedures). The DR log carried the rationale but nothing
  stated the documentation architecture itself.
- **Decision:** the documentation is split by audience into three types in
  `docs/`, plus the decision log:
  - `docs/requirements.md` (BRD) — *what* the dotfiles must achieve and
    where: scope matrix, accepted limitations per environment, functional
    and non-functional requirements, non-goals, accepted risks;
  - `docs/system.md` (SRD) — *how* the system works: components, startup
    chains per environment, the `profile.d/` contract, tool wiring, data
    and side effects, deploy/lint/embed procedures;
  - `docs/design.md` (TDD) — *why* it is built this way: mechanisms,
    constraints, invariants, gotchas, grouped by DR-###;
  - `DECISIONS.md` — the dated decision log (ADR-lite); the single source
    for every DR-### reference.
  `README.md` is an index into these, not a content home. Documentation
  drift is tracked in `docs/known-issues.md`.
- **Boundary looseness (deliberate):** the types are kept as guidance, not
  straitjackets. The BRD may cite DR numbers, env vars and file names, and
  the SRD may cover repo tooling (`lint.sh`, `embed.mjs`/`unembed.mjs`) —
  with a single owner-developer as the only stakeholder, a purist BRD would
  be empty formalism and the whole repo *is* the system. If the audience
  ever broadens, tighten the boundaries then.
- **Consequences:** three content files can drift from each other and from
  the code; mitigated by `docs/known-issues.md` (working list of
  discrepancies, entries removed once fixed and recorded in a DR). The
  decision log remains the single authoritative record; the three types are
  views over it, not alternative sources of truth.

## DR-036 | Termux `shortcuts/tasks/*.sh` maintained as real files, deployed via `cp` | Accepted (applied) | 2026-09-19

- **Context:** The two Termux:Widget background tasks (sshd restart, ip.json
  refresh) shipped as un-lintable heredoc copies inside `deploy.sh` — the
  bodies were invisible to `lint.sh`, drift-prone, and duplicated the logic of
  `profile.d/50_ip.sh`. The doc chain still claimed the Termux scaffolding was
  "empty dirs, nothing is populated", and the DR-016 invariant said
  `deploy.sh` only ever copies `src-dotfiles.sh`.
- **Decision:** Maintain the tasks as real, lintable script files under
  `shortcuts/tasks/` (`sshd.sh`, `ip.sh`) and have `deploy.sh` copy them
  verbatim into `~/.shortcuts/tasks/` (chmod 700) on Termux only. `ip.sh`
  bundles `profile.d/50_ip.sh`'s Markor JSON write (minus the interactive-only
  guard — widget tasks are non-interactive) plus an IPv4 toast (jq preferred,
  awk fallback). The tasks source `src-dotfiles.sh` like any Termux entrypoint
  so PATH/PREFIX are available. `lint.sh`'s existing `*.sh` glob already
  covers the new directory, so the tasks are linted with the rest of the repo
  (SC1090 on the dynamic source suppressed with `source=/dev/null`, SC2312 on
  the toast handled with `|| true`).
- **Consequences:** The heredoc copies (and the `termux-shortcuts.html`
  embedding) are gone — one source of truth, real diffs, linted. The stale
  "nothing is populated" doc claims and the DR-016 invariant wording were
  updated accordingly. `deploy.sh` remains idempotent (cp over identical
  content is a no-op); non-Termux hosts still skip the branch entirely.
