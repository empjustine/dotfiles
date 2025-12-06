#!/bin/sh

if [ -n "$WSL_DISTRO_NAME" ]; then

	# normal linux: printenv XDG_RUNTIME_DIR
	# /run/user/1000
	# wsl2: printenv XDG_RUNTIME_DIR
	# /run/user/1000/
	XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR%/}"

	# podman container run
	# WARN[0000] "/" is not a shared mount, this could cause issues or missing mounts with rootless containers
	if [ "$(findmnt --noheadings -o PROPAGATION /)" = "private" ]; then
		sudo mount --make-shared /
	fi

	wsl2_mountpoint="/mnt/wsl/${WSL_DISTRO_NAME}"
	if ! findmnt --mountpoint="$wsl2_mountpoint" >/dev/null; then
		mkdir -p -- "$wsl2_mountpoint"
		sudo mount --bind / "$wsl2_mountpoint"
	fi
	unset wsl2_mountpoint

	if [ -x /usr/bin/gnome-keyring-daemon ] && [ -z "$GNOME_KEYRING_CONTROL" ]; then
		eval "$(/usr/bin/gnome-keyring-daemon --start --components=secrets 2>/dev/null)"
		export GNOME_KEYRING_CONTROL
	fi
fi
