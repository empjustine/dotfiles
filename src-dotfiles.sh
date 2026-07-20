#!/bin/sh
# Unified dotfiles entrypoint — the single source of truth for shell startup.
#
# Deploy it (or copy its contents) to the four standard rc files:
#   ~/.bash_profile  ~/.bashrc  ~/.zprofile  ~/.zshrc
# It then loops over $DOTFILES/profile.d and sources each snippet:
#   *.sh   — POSIX, sourced by every shell
#            (under zsh this is wrapped in `emulate -L ksh` so options stay
#             local to the helper while the snippet's exports still escape)
#   *.bash — bash-only
#   *.zsh  — zsh-only
#
# For /etc/profile.d deployment the interpreter is dash, so *.sh files must
# stay POSIX-clean (no [[, no <(...), no `local`, no `source`).

_src_one() {
	rc="$1"
	[ -r "$rc" ] || return 0
	case "$rc" in
		*.sh)
			if [ -n "$ZSH_VERSION" ]; then
				emulate -L ksh
			fi
			# shellcheck source=/dev/null
			. "$rc"
			;;
		*.bash)
			[ -n "$BASH_VERSION" ] && . "$rc"
			;;
		*.zsh)
			[ -n "$ZSH_VERSION" ] && . "$rc"
			;;
	esac
}

for rc in "${DOTFILES:-$HOME/dotfiles}/profile.d/"*; do
	_src_one "$rc"
done

unset -f _src_one
unset rc
