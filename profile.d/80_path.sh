#!/bin/sh
# 80_path.sh — PATH policy (DR-014, DR-033; the Win32 regime went with
# DR-038).
#
# Gate: none, but the wholesale reset is skipped on cloud shells and Termux,
# which own their PATH. Side effect: replaces PATH on desktop/WSL2 hosts
# (ANDROID_HOME moved to 10_env.sh — DR-038 split).
# Side effect also adds the repo-owned bin/ (tmux-profiles, DR-046); the
# stock per-user dirs stay out (DR-033).

# Cloud shells and Termux pre-build a correct PATH we must not disturb
# ("don't mangle cursed $PATH", DR-014). Same markers 20_core.bash uses to
# decide which system rc to source.
if [ -r /etc/bashrc.cloudshell ] \
	|| [ -r /google/devshell/bashrc.google ] \
	|| [ -d /data/data/com.termux/files/usr ]; then
	:
else
	PATH="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:${MISE_SYSTEM_DATA_DIR:-/usr/local/share/mise}/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"

	# Deliberately excluded from the reset (DR-033): the stock per-user PATH
	# extension points — ~/.local/bin, ~/bin, ~/.bin, ~/.shortcuts — and
	# installer dirs (.dotnet/tools, JetBrains Toolbox). profile.d/ stays the
	# shell extension point; the repo's own bin/ is the one versioned PATH
	# entry, for tmux-profiles (DR-046).
	#	"${HOME}/.local/bin" \
	#	"${HOME}/.dotnet/tools" \
	#	"${XDG_DATA_HOME:-$HOME/.local/share}/JetBrains/Toolbox/scripts" \
	for dir in \
		"${DOTFILES:-$HOME/dotfiles}/bin" \
		"${HOME}/.pi/agent/bin" \
		"/run/media/deck/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/var/home/deck/projects/bin" \
		"/home/linuxbrew/.linuxbrew/sbin" \
		"/home/linuxbrew/.linuxbrew/bin" \
		"/usr/lib/wsl/lib"; do
		[ -d "${dir}" ] && PATH="${PATH}:${dir}"
	done
	unset dir
fi
