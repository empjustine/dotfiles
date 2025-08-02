#!/usr/bin/env zsh

if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"
fi

if [ -x /home/linuxbrew/.linuxbrew/bin/mise ]; then
	if [ -n "$PS1" ]; then
		eval "$(/home/linuxbrew/.linuxbrew/bin/mise activate zsh)"
	else
		eval "$(/home/linuxbrew/.linuxbrew/bin/mise activate --shims)"
	fi
fi
