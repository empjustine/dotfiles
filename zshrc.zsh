#!/usr/bin/env zsh

for rc in "${DOTFILES:-$HOME/dotfiles}/zshrc.d/"*; do
	[ -r "$rc" ] && . "$rc"
done
unset rc
