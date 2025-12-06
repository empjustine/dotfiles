#!/bin/bash
for rc in "${DOTFILES:-$HOME/dotfiles}/profile.d/"*; do
	if [ -r "$rc" ]; then
		case "$rc" in
			*.sh)
				. "$rc"
				;;
			*.bash)
				. "$rc"
				;;
			*) ;;
		esac
	fi
done
unset rc
