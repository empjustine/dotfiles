#!/bin/bash
# 70_history.bash — atuin history hooks, interactive bash (DR-016, DR-037).
#
# Gate: bash only, interactive only. bash has no native preexec, so atuin
# installs its own bash-preexec at `atuin init` time — the known random
# history loss lives on this path: read docs/execution-map.md §10 before
# changing the invocation.

[ -n "$BASH_VERSION" ] || {
	printf '%s\n' "dotfiles: bash-only snippet sourced under a non-bash shell; skipping" >&2
	return 0
}

case "$-" in
	*i*) ;;
	*) return 0 ;;
esac

# Allowlisted atuin locations, in priority order. An arbitrary
# atuin resolved from $PATH is intentionally NOT trusted. Termux
# and the system "local" atuin are last (fallback only).
atuin_bin=""
mise_attempted=""
for cand in \
	"${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims/atuin" \
	"$HOME/.local/share/mise/shims/atuin" \
	"${MISE_SYSTEM_DATA_DIR:-/usr/local/share/mise}/shims/atuin" \
	/usr/local/share/mise/shims/atuin \
	/home/linuxbrew/.linuxbrew/bin/atuin \
	/data/data/com.termux/files/usr/bin/atuin \
	/usr/bin/atuin; do
	[ -x "$cand" ] || continue
	# A mise shim can exist yet have no version selected
	# (`mise ERROR No version is set for shim: atuin`, exit 1).
	# Verify the binary actually runs before trusting it.
	if ! "$cand" --version >/dev/null 2>&1; then
		case "$cand" in
			*/mise/shims/atuin)
				if [ -z "$mise_attempted" ] && command -v mise >/dev/null 2>&1; then
					mise use -g atuin >/dev/null 2>&1
					mise_attempted=1
				fi
				"$cand" --version >/dev/null 2>&1 || continue
				;;
			*)
				continue
				;;
		esac
	fi
	atuin_bin="$cand"
	break
done
unset cand mise_attempted

if [ -n "$atuin_bin" ]; then
	# atuin ≥ 18.18.x bundles bash-preexec (V0.7.0) itself and auto-loads it at
	# `atuin init` time when no other preexec backend is present (DR-025,
	# DR-037) — nothing is sourced here; atuin's bundled copy is the backend.
	#
	# Never `|| true` this. An init that prints nothing installs no hooks, and
	# the shell then records history into nowhere while looking perfectly
	# healthy (DR-044).
	_atuin_init="$("$atuin_bin" init bash --disable-up-arrow)"
	_atuin_rc=$?
	if [ "$_atuin_rc" -ne 0 ] || [ -z "$_atuin_init" ]; then
		printf '%s\n' "dotfiles: 'atuin init bash' produced no script (exit $_atuin_rc) — history capture is OFF in this shell (DR-044)" >&2
	else
		eval "$_atuin_init"
		# The generated hooks call bare `atuin` from $PATH, not the binary wired
		# up here. Two different atuins (or none) means every command goes to a
		# different database, or to nothing, with no error at all (DR-044).
		_atuin_hook_bin="$(command -v atuin 2>/dev/null)"
		if [ -z "$_atuin_hook_bin" ]; then
			printf '%s\n' "dotfiles: atuin is not on \$PATH, so the history hook records nothing (DR-044)" >&2
		elif [ "$_atuin_hook_bin" != "$atuin_bin" ]; then
			# A mise shim for init and mise's own bin at prompt time is the normal
			# case; anything else means two different atuins.
			case "$atuin_bin:$_atuin_hook_bin" in
				*mise*:*mise*) : ;;
				*) printf '%s\n' "dotfiles: the history hook will call $_atuin_hook_bin, not the $atuin_bin it was wired from — history may go elsewhere (DR-044)" >&2 ;;
			esac
		fi
		unset _atuin_hook_bin
	fi
	unset _atuin_init _atuin_rc
elif command -v atuin >/dev/null 2>&1; then
	# atuin exists but not where this repo trusts it (DR-016): the hooks are
	# off, which would otherwise look exactly like random history loss (DR-044).
	printf '%s\n' "dotfiles: atuin is on \$PATH but in no allowlisted location — history hooks are off (DR-016, DR-044)" >&2
fi

unset atuin_bin
