#!/bin/sh

if [ -n "$PS1" ]; then
	if [ -n "$BASH_VERSION" ]; then
		if [ -x "/home/linuxbrew/.linuxbrew/bin/atuin" ] && [ -r "/home/linuxbrew/.linuxbrew/etc/profile.d/bash-preexec.sh" ]; then
			eval "$(atuin init bash --disable-up-arrow || true)"
			. /home/linuxbrew/.linuxbrew/etc/profile.d/bash-preexec.sh
		fi
	elif [ -n "$ZSH_VERSION" ]; then
		[ -x /home/linuxbrew/.linuxbrew/bin/atuin ] && eval "$(/home/linuxbrew/.linuxbrew/bin/atuin init zsh --disable-up-arrow || true)"
		[ -x /data/data/com.termux/files/usr/bin/atuin ] && eval "$(/data/data/com.termux/files/usr/bin/atuin init zsh --disable-up-arrow || true)"
	fi
fi
