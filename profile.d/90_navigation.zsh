#!/bin/zsh

[ -n "$ZSH_VERSION" ] || { printf '%s\n' "dotfiles: zsh-only snippet sourced under a non-zsh shell; skipping" >&2; return 0; }

# The keybinds are only meaningful on xterm-256color; other TERM values
# keep zsh defaults (absence of binds here is NOT a wrong-shell error).
if [ "$TERM" = "xterm-256color" ]; then
	case "$-" in
		*i*) ;;
		*) return 0 ;;
	esac

	# ptyxis
	# vscode xterm.js
	# idea integrated terminal

	bindkey -e

	bindkey "^[[1;5C" forward-word
	bindkey "^[[1;5D" backward-word

	bindkey "^[[3~" delete-char
	bindkey "^[[F" end-of-line
	bindkey "^[[H" beginning-of-line
fi
