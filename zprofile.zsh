#!/bin/zsh

_src_ksh() {
	emulate -L ksh
	. "$1"
}
for rc in "${DOTFILES:-$HOME/dotfiles}/profile.d/"*; do
	if [ -r "$rc" ]; then
		case "$rc" in
			*.sh)
				_src_ksh "$rc"
				;;
			*.zsh)
				source "$rc"
				;;
			*) ;;
		esac
	fi
done
unset -f _src_ksh
unset rc
