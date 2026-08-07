#!/bin/sh

set -x

for target in "$HOME/.bash_profile" "$HOME/.bashrc"; do
	cp "${DOTFILES:-$HOME/dotfiles}/src-dotfiles.sh" "$target"
done

# Deploy the zsh entrypoints only when zsh exists; on Git Bash / MSYS2 the
# Windows profile would otherwise collect stray .zshrc/.zprofile files.
if command -v zsh >/dev/null 2>&1; then
	for target in "${ZDOTDIR:-$HOME}/.zprofile" "${ZDOTDIR:-$HOME}/.zshrc"; do
		cp "${DOTFILES:-$HOME/dotfiles}/src-dotfiles.sh" "$target"
	done
fi

if [ -d /data/data/com.termux/files/usr ]; then
	# Termux: $PREFIX/etc/profile sources ~/.bashrc itself (interactive bash),
	# and bash then also reads ~/.bash_profile. Keep both files: .bashrc
	# covers login + non-login interactive, .bash_profile covers non-interactive
	# login shells (ssh); the idempotency guard in src-dotfiles.sh makes the
	# login double-read a no-op.
	mkdir -p -- ~/.termux/boot ~/.shortcuts/tasks ~/bin
	chmod 700 -R ~/.termux/boot ~/.shortcuts/tasks ~/bin
fi