#!/usr/bin/env zsh

# @see https://zsh.sourceforge.io/Guide/zshguide02.html#l9

_ZPROFILE="${_ZPROFILE}${_ZPROFILE:+;}$(date --iso-8601=ns)"
export _ZPROFILE

for rc in "${DOTFILES:-$HOME/dotfiles}/zprofile.d/"*; do
	[ -r "$rc" ] && . "$rc"
done
unset rc
