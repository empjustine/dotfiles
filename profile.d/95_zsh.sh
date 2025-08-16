#!/bin/sh

if [ -n "$PS1" ]; then
	if [ -n "$BASH_VERSION" ] || [ -n "$KSH_VERSION" ]; then
		if [ -x /bin/zsh ]; then
			/bin/zsh
		elif [ -x /data/data/com.termux/files/usr/bin/zsh ]; then
			/data/data/com.termux/files/usr/bin/zsh
		fi
	fi
fi
