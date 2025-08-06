#!/usr/bin/env zsh

# debug: od -c

if [ -n "$PS1" ] && [ "$TERM" = "xterm-256color" ]; then
	# ptyxis
	# vscode xterm.js
	# idea integrated terminal

	bindkey "^[[1;5C" forward-word
	bindkey "^[[1;5D" backward-word

	bindkey "^[[3~" delete-char
	bindkey "^[[F" end-of-line
	bindkey "^[[H" beginning-of-line
fi
