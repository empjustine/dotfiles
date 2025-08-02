#!/usr/bin/env zsh

for rc in "${DOTFILES:-$HOME/dotfiles}/zprofile.d/"*; do
	[ -r "$rc" ] && . "$rc"
done
unset rc
