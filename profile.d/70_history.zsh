#!/bin/zsh
# 70_history.zsh — atuin history hooks, interactive zsh (DR-016, DR-037).
#
# Gate: zsh only, interactive only. zsh has native precmd/preexec, so no
# bash-preexec is involved — this is the healthy counterpart of the bash
# path described in docs/execution-map.md §10.

[ -n "$ZSH_VERSION" ] || { printf '%s\n' "dotfiles: zsh-only snippet sourced under a non-zsh shell; skipping" >&2; return 0; }

case "$-" in
	*i*) ;;
	*) return 0 ;;
esac

# Allowlisted atuin locations, in priority order. An arbitrary
# atuin resolved from $PATH is intentionally NOT trusted. Termux
# and the system "local" atuin are last (fallback only). zsh has
# native preexec/precmd hooks, so no bash-preexec is needed.
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
	# Not `|| true`: see 70_history.bash and DR-044 — a silent init leaves the
	# shell with no hooks and no complaint.
	_atuin_init="$("$atuin_bin" init zsh --disable-up-arrow)"
	_atuin_rc=$?
	if [ "$_atuin_rc" -ne 0 ] || [ -z "$_atuin_init" ]; then
		printf '%s\n' "dotfiles: 'atuin init zsh' produced no script (exit $_atuin_rc) — history capture is OFF in this shell" >&2
	else
		eval "$_atuin_init"
		_atuin_hook_bin="$(command -v atuin 2>/dev/null)"
		if [ -z "$_atuin_hook_bin" ]; then
			printf '%s\n' "dotfiles: atuin is not on \$PATH, so the history hook records nothing (DR-044)" >&2
		elif [ "$_atuin_hook_bin" != "$atuin_bin" ]; then
			case "$atuin_bin:$_atuin_hook_bin" in
				*mise*:*mise*) : ;;
				*) printf '%s\n' "dotfiles: the history hook will call $_atuin_hook_bin, not the $atuin_bin it was wired from — history may go elsewhere (DR-044)" >&2 ;;
			esac
		fi
		unset _atuin_hook_bin
	fi
	unset _atuin_init _atuin_rc
elif command -v atuin >/dev/null 2>&1; then
	printf '%s\n' "dotfiles: atuin is on \$PATH but in no allowlisted location — history hooks are off (DR-016, DR-044)" >&2
fi

unset atuin_bin
