#!/bin/zsh

if [ -n "$PS1" ] && [ -n "$ZSH_VERSION" ]; then
	[ -x /home/linuxbrew/.linuxbrew/bin/atuin ] && eval "$(/home/linuxbrew/.linuxbrew/bin/atuin init zsh --disable-up-arrow || true)"
	[ -x /data/data/com.termux/files/usr/bin/atuin ] && eval "$(/data/data/com.termux/files/usr/bin/atuin init zsh --disable-up-arrow || true)"
fi
