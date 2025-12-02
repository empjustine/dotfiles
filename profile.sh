#!/bin/sh

for rc in "${DOTFILES:-$HOME/dotfiles}/profile.d/"*; do
	[ -r "$rc" ] && . "$rc"
done
unset rc
