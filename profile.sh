#!/bin/sh

# @see https://zsh.sourceforge.io/Guide/zshguide02.html#l9

_PROFILE="${_PROFILE}${_PROFILE:+;}$(date --iso-8601=ns)"
export _PROFILE

for rc in "${DOTFILES:-$HOME/dotfiles}/profile.d/"*; do
	[ -r "$rc" ] && . "$rc"
done
unset rc
