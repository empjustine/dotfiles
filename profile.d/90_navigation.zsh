#!/bin/zsh

if [ -n "$ZSH_VERSION" ] && [ "$TERM" = "xterm-256color" ]; then
	case "$-" in
		*i*)
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
			;;
	esac
else
	printf '%s\n' "dotfiles: zsh-only snippet sourced under a non-zsh shell; skipping" >&2
fi
