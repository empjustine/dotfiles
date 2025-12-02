#!/bin/sh

if [ -n "$PS1" ] && [ -n "$ZSH_VERSION" ] && [ "$TERM" = "xterm-256color" ]; then
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
