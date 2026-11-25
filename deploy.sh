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

# Deploy the zsh entrypoints only when zsh exists (a fresh Silverblue or a
# cloud image may have none): no stray .zshrc/.zprofile on those hosts.
if command -v zsh >/dev/null 2>&1; then
	for target in "${ZDOTDIR:-$HOME}/.zprofile" "${ZDOTDIR:-$HOME}/.zshrc"; do
		cp "${DOTFILES:-$HOME/dotfiles}/src-dotfiles.sh" "$target"
	done
fi

# Atuin >= 18.18 tags history entries with their originating shell and
# `search.shells = "auto"` (the default) then hides zsh commands from bash
# interactive search and vice versa. Set the shared view once at deploy time.
# Use the same allowlisted discovery as 70_history.{bash,zsh} (DR-016) and let
# Atuin edit its own config so comments/formatting survive.
atuin_bin=""
for cand in \
	"${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims/atuin" \
	"$HOME/.local/share/mise/shims/atuin" \
	"${MISE_SYSTEM_DATA_DIR:-/usr/local/share/mise}/shims/atuin" \
	/usr/local/share/mise/shims/atuin \
	"${XDG_DATA_HOME:-$HOME/.local/share}"/mise/installs/atuin/*/atuin-*/atuin \
	"${MISE_SYSTEM_DATA_DIR:-/usr/local/share/mise}"/installs/atuin/*/atuin-*/atuin \
	/home/linuxbrew/.linuxbrew/bin/atuin \
	/data/data/com.termux/files/usr/bin/atuin \
	/usr/bin/atuin; do
	[ -x "$cand" ] || continue
	"$cand" --version >/dev/null 2>&1 || continue
	atuin_bin="$cand"
	break
done
if [ -n "$atuin_bin" ] && ! "$atuin_bin" config set search.shells all; then
	printf '%s\n' "deploy: atuin config set search.shells all failed" >&2
fi
unset atuin_bin cand

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

# systemd hosts: install the two tmux profile units and the daily upkeep
# timer (DR-046). The user bus must already be up (lingering) and tmux must
# exist, otherwise enable --now would leave a failing unit on the host.
if [ "$TERMUX" -eq 0 ] && command -v tmux >/dev/null 2>&1 \
	&& command -v systemctl >/dev/null 2>&1 \
	&& systemctl --user is-active default.target >/dev/null 2>&1; then
	units="${DOTFILES:-$HOME/dotfiles}/config/systemd/user"
	config="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
	mkdir -p -- "$config"
	for unit in "$units"/*.service "$units"/*.timer; do
		[ -f "$unit" ] || continue
		cp "$unit" "$config/$(basename "$unit")"
	done
	systemctl --user daemon-reload
	systemctl --user enable --now tmux-fg.service tmux-bg.service tmux-upkeep.timer
	unset unit units config
fi
