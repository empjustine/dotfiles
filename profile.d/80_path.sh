#!/bin/sh

if [ -d "${HOME}/Android/Sdk" ]; then
	ANDROID_HOME="${HOME}/Android/Sdk"
	export ANDROID_HOME
fi

if [ "$OCI_CLI_CLOUD_SHELL" = "True" ]; then
	:
elif [ -d "/data/data/com.termux/files/usr" ]; then
	# termux $PREFIX
	:
else
	PATH="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"

	for dir in \
		"${XDG_DATA_HOME:-$HOME/.local/share}/JetBrains/Toolbox/scripts" \
		"/run/media/deck/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/var/home/deck/projects/bin" \
		"/home/linuxbrew/.linuxbrew/sbin" \
		"/home/linuxbrew/.linuxbrew/bin" \
		"${HOME}/.local/bin" \
		"${HOME}/.dotnet/tools" \
		"/usr/lib/wsl/lib"; do
		[ -d "${dir}" ] && PATH="${PATH}:${dir}"
	done
	unset dir
fi
