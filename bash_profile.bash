#!/bin/bash

for rc in "${DOTFILES:-$HOME/dotfiles}/bash_profile.d/"*; do
	[ -r "$rc" ] && . "$rc"
done
unset rc
