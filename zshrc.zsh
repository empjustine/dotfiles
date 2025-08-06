#!/usr/bin/env zsh

# @see https://zsh.sourceforge.io/Guide/zshguide02.html#l9

_ZSHRC="${_ZSHRC}${_ZSHRC:+;}$(date --iso-8601=ns)"
export _ZSHRC

for rc in "${DOTFILES:-$HOME/dotfiles}/zshrc.d/"*; do
	[ -r "$rc" ] && . "$rc"
done
unset rc
