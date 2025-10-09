#!/bin/sh

if [ -n "$PS1" ]; then
	if [ -n "$BASH_VERSION" ] || [ -n "$KSH_VERSION" ]; then
		if [ -x /bin/zsh ]; then
			: /bin/zsh
		elif [ -x /data/data/com.termux/files/usr/bin/zsh ]; then
			: /data/data/com.termux/files/usr/bin/zsh
		fi
	elif [ -n "$ZSH_VERSION" ] && [ "$TERM" = "xterm-256color" ]; then
        	# ptyxis
        	# vscode xterm.js
        	# idea integrated terminal

        	# debug: od -c
        	bindkey -e

        	bindkey "^[[1;5C" forward-word
        	bindkey "^[[1;5D" backward-word

        	bindkey "^[[3~" delete-char
        	bindkey "^[[F" end-of-line
        	bindkey "^[[H" beginning-of-line
        fi
fi
