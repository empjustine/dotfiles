#!/bin/sh

if [ -n "$DISPLAY" ]; then
	systemctl --user import-environment DISPLAY
fi

if [ -n "$WAYLAND_DISPLAY" ]; then
	systemctl --user import-environment WAYLAND_DISPLAY
fi

if [ -n "$WSL_DISTRO_NAME" ]; then

	# normal linux: printenv XDG_RUNTIME_DIR
	# /run/user/1000
	# wsl2: printenv XDG_RUNTIME_DIR
	# /run/user/1000/
	XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR%/}"

	# podman container run
	# WARN[0000] "/" is not a shared mount, this could cause issues or missing mounts with rootless containers
	_PROPAGATION="$(findmnt --noheadings -o PROPAGATION /)"
	if [ "$_PROPAGATION" = "private" ]; then
		sudo mount --make-shared /
	fi

	# bind mount shared directory
	mkdir -p -- "/mnt/wsl/${WSL_DISTRO_NAME}"
	if ! findmnt --mountpoint="/mnt/wsl/${WSL_DISTRO_NAME}" >/dev/null; then
		sudo mount --bind / "/mnt/wsl/${WSL_DISTRO_NAME}"
	fi

	# ensure /usr/lib/wsl/lib lowest priority in PATH
	case "$PATH" in
		*:/usr/lib/wsl/lib:*)
			PATH="${PATH%%:/usr/lib/wsl/lib:*}:/usr/lib/wsl/lib"
			;;
	esac
fi
