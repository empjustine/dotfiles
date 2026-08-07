#!/bin/sh

if [ -d "${HOME}/Android/Sdk" ]; then
	ANDROID_HOME="${HOME}/Android/Sdk"
	export ANDROID_HOME
fi

case "$(uname -s)" in
	*MINGW*|*MSYS*|*CYGWIN*)
		# Git Bash / MSYS2 / Cygwin on Win32: PATH is owned by Windows
		# (System32, per-user dirs, scoop shims). Never reset it here —
		# native executables would become unreachable. Just make sure
		# scoop's shim dir and mise's Windows dirs are present (fresh
		# installs may not be in the inherited Windows PATH yet): the
		# mise binary itself lives in %LOCALAPPDATA%\mise\bin, its
		# per-tool shims in %LOCALAPPDATA%\mise\shims.
		if [ -d "${SCOOP:-$HOME/scoop}/shims" ]; then
			scoop_shims="${SCOOP:-$HOME/scoop}/shims"
			case ":$PATH:" in
				*":$scoop_shims:"*) ;;
				*) PATH="$PATH:$scoop_shims" ;;
			esac
			SCOOP="${SCOOP:-$HOME/scoop}"
			export SCOOP
			unset scoop_shims
		fi
		for dir in \
			"${LOCALAPPDATA:-$HOME/AppData/Local}/mise/bin" \
			"${LOCALAPPDATA:-$HOME/AppData/Local}/mise/shims"; do
			[ -d "$dir" ] || continue
			case ":$PATH:" in
				*":$dir:"*) ;;
				*) PATH="$PATH:$dir" ;;
			esac
		done
		unset dir
		;;
	*)
		if [ -r /etc/bashrc.cloudshell ]; then
			:
		elif [ -r /google/devshell/bashrc.google ]; then
			:
		elif [ -d /data/data/com.termux/files/usr ]; then
			:
		else
			PATH="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:${MISE_SYSTEM_DATA_DIR:-/usr/local/share/mise}/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"

			#	"${HOME}/.local/bin" \
			#	"${HOME}/.dotnet/tools" \
			#	"${XDG_DATA_HOME:-$HOME/.local/share}/JetBrains/Toolbox/scripts" \
			for dir in \
				"/run/media/deck/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/var/home/deck/projects/bin" \
				"/home/linuxbrew/.linuxbrew/sbin" \
				"/home/linuxbrew/.linuxbrew/bin" \
				"/usr/lib/wsl/lib"; do
				[ -d "${dir}" ] && PATH="${PATH}:${dir}"
			done
			unset dir
		fi
		;;
esac
