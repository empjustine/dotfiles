#!/bin/bash

if [ -n "$PS1" ] && [ -n "$BASH_VERSION" ]; then
	if [ -x "/home/linuxbrew/.linuxbrew/bin/atuin" ]; then
		eval "$(/home/linuxbrew/.linuxbrew/bin/atuin init bash --disable-up-arrow || true)"
		. "${DOTFILES:-$HOME/dotfiles}/bash-preexec.sh"
	elif [ -x "/data/data/com.termux/files/usr/bin/atuin" ]; then
		eval "$(/data/data/com.termux/files/usr/bin/atuin init bash --disable-up-arrow || true)"
		. "${DOTFILES:-$HOME/dotfiles}/bash-preexec.sh"
	fi
fi
