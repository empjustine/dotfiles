#!/bin/bash

for rc in "${DOTFILES:-$HOME/dotfiles}/bashrc.d/"*; do
	[ -r "$rc" ] && . "$rc"
done
unset rc
