#!/bin/sh

if [ -d "${HOME}/Android/Sdk" ]; then
	ANDROID_HOME="${HOME}/Android/Sdk"
	export ANDROID_HOME
fi

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
	# installer dirs (.dotnet/tools, JetBrains Toolbox). The supported
	# extension point is profile.d/ in the dotfiles repo, not PATH additions.
	#	"${HOME}/.local/bin" \
	#	"${HOME}/.dotnet/tools" \
	#	"${XDG_DATA_HOME:-$HOME/.local/share}/JetBrains/Toolbox/scripts" \
	for dir in \
		"${HOME}/.pi/agent/bin" \
		"/run/media/deck/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/var/home/deck/projects/bin" \
		"/home/linuxbrew/.linuxbrew/sbin" \
		"/home/linuxbrew/.linuxbrew/bin" \
		"/usr/lib/wsl/lib"; do
		[ -d "${dir}" ] && PATH="${PATH}:${dir}"
	done
	unset dir
fi
