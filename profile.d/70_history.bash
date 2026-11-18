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
	# atuin ≥ 18.18.x bundles bash-preexec (V0.7.0) itself and
	# auto-loads it at `atuin init` time when no other preexec
	# backend (ble.sh, external bash-preexec) is present; loading an
	# external copy first would set bash_preexec_imported and make
	# atuin skip its newer, history-reliable builtin (DR-025,
	# DR-037). The vendored bash-preexec.sh is therefore no longer
	# sourced — atuin's bundled one is the only preexec backend.
	# shellcheck source=/dev/null
	eval "$("$atuin_bin" init bash --disable-up-arrow || true)"
fi

unset atuin_bin
