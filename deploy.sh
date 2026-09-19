#!/bin/sh

# Deploy the dotfiles entrypoints (rc targets are copies of
# src-dotfiles.sh, plus src-dotfiles.ps1's manual wire-up) and the
# Termux-only scaffolding: the Termux:Widget script directories plus the
# two ~/.shortcuts/tasks background task scripts (sshd restart, ip.json
# refresh). Everything is idempotent; non-Termux hosts skip the Termux
# branch entirely.

set -x

if [ -d /data/data/com.termux/files/usr ]; then
	# Termux: $PREFIX/etc/profile sources ~/.bashrc itself (interactive
	# bash), and bash then also reads ~/.bash_profile. Keep both files:
	# .bashrc covers login + non-login interactive, .bash_profile covers
	# non-interactive login shells (ssh); the idempotency guard in
	# src-dotfiles.sh makes the login double-read a no-op.
	TERMUX=1
else
	TERMUX=0
fi

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

# Termux-only: scaffold the Termux:Widget/Boot directories (chmod 700,
# empty except for the task scripts below) and copy the background-task
# scripts into ~/.shortcuts/tasks. Unlike the rc entrypoints these are
# maintained as real files under shortcuts/tasks/ (linted by lint.sh),
# then installed here via cp — no stale copies, no heredoc content.
if [ "$TERMUX" -eq 1 ]; then
	mkdir -p -- ~/.termux/boot ~/.termux/widget/dynamic_shortcuts ~/.shortcuts/tasks ~/bin
	chmod 700 -R ~/.termux/boot ~/.termux/widget/dynamic_shortcuts ~/.shortcuts/tasks ~/bin

	cp "${DOTFILES:-$HOME/dotfiles}/shortcuts/tasks/sshd.sh" ~/.shortcuts/tasks/sshd.sh
	cp "${DOTFILES:-$HOME/dotfiles}/shortcuts/tasks/ip.sh" ~/.shortcuts/tasks/ip.sh
	chmod 700 ~/.shortcuts/tasks/sshd.sh ~/.shortcuts/tasks/ip.sh
fi
