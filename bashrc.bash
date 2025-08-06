#!/bin/bash

# @see https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html#Invoked-as-an-interactive-non_002dlogin-shell

_BASH_RC="${_BASH_RC}${_BASH_RC:+;}$(date --iso-8601=ns)"
export _BASH_RC

for rc in "${DOTFILES:-$HOME/dotfiles}/bashrc.d/"*; do
	[ -r "$rc" ] && . "$rc"
done
unset rc
