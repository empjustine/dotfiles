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
# empty except for the tasks below) and install the background task
# scripts into ~/.shortcuts/tasks. Quoted heredocs keep the bodies
# verbatim; each task sources src-dotfiles.sh first, like any Termux
# entrypoint, so PATH/PREFIX are set up before the work runs.
if [ "$TERMUX" -eq 1 ]; then
	mkdir -p -- ~/.termux/boot ~/.termux/widget/dynamic_shortcuts ~/.shortcuts/tasks ~/bin
	chmod 700 -R ~/.termux/boot ~/.termux/widget/dynamic_shortcuts ~/.shortcuts/tasks ~/bin

	# Restart the sshd service and toast its status (background task;
	# the same script termux-shortcuts.html used to embed).
	cat >~/.shortcuts/tasks/sshd.sh <<'__TERMUX_SSHD__'
#!/data/data/com.termux/files/usr/bin/sh

. ~/dotfiles/src-dotfiles.sh

set -x

#SVDIR=$PREFIX/var/service
SVDIR=/data/data/com.termux/files/usr/var/service
LOGDIR=/data/data/com.termux/files/usr/var/log

export SVDIR
export LOGDIR
sv down sshd
pkill sshd
sv up sshd

termux-toast "$(sv status sshd)"
__TERMUX_SSHD__

	# profile.d/50_ip.sh's logic as a standalone task: refresh the LAN-IP
	# JSON for Markor on demand. The interactive-only guard is dropped —
	# the widget spawns non-interactive shells, where the guard in the
	# profile snippet would otherwise skip the write.
	cat >~/.shortcuts/tasks/ip.sh <<'__TERMUX_IP__'
#!/data/data/com.termux/files/usr/bin/sh

. ~/dotfiles/src-dotfiles.sh

if [ -d ~/storage/shared/Documents/markor ]; then
	ip --json addr >~/storage/shared/Documents/markor/ip.json
fi

# Toast a usable response: the primary IPv4 (the first inet address on
# the first interface), which the JSON's full dump is not. jq is
# preferred; fall back to awk when missing.
ip4=$(ip --json addr show dev wlan0 2>/dev/null | jq -r '.[0].addr_info[] | select(.family == "inet") | .local' 2>/dev/null | head -1)
if [ -z "$ip4" ]; then
	ip4=$(ip -4 addr show dev wlan0 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)
fi
if [ -n "$ip4" ]; then
	termux-toast "wlan0: $ip4"
else
	termux-toast "ip.json updated"
fi
__TERMUX_IP__
	chmod 700 ~/.shortcuts/tasks/sshd.sh ~/.shortcuts/tasks/ip.sh
fi
