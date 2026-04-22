#!/bin/bash
for rc in "${DOTFILES:-$HOME/dotfiles}/profile.d/"*; do
	if [ -r "$rc" ]; then
		case "$rc" in
			*.sh)
				# shellcheck source=/dev/null
				. "$rc"
				;;
			*.bash)
				# shellcheck source=/dev/null
				. "$rc"
				;;
			*) ;;
		esac
	fi
done
unset rc
