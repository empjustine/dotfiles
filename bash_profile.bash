#!/bin/bash

# @see https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html#Invoked-as-an-interactive-login-shell_002c-or-with-_002d_002dlogin

_BASH_PROFILE="${_BASH_PROFILE}${_BASH_PROFILE:+;}$(date --iso-8601=ns)"
export _BASH_PROFILE

for rc in "${DOTFILES:-$HOME/dotfiles}/bash_profile.d/"*; do
	[ -r "$rc" ] && . "$rc"
done
unset rc
