#!/bin/sh

if [ -n "$WSL_DISTRO_NAME" ]; then

	# normal linux: printenv XDG_RUNTIME_DIR
	# /run/user/1000
	# wsl2: printenv XDG_RUNTIME_DIR
	# /run/user/1000/
	XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR%/}"

	# Only do privileged setup in interactive shells; skip non-interactive
	# (ssh host command, scp, CI) where sudo may hang or be pointless.
	if [ -n "$PS1" ]; then
		# fstrim is heavy and already handled by systemd timers: throttle to
		# once per boot via a stamp in XDG_RUNTIME_DIR.
		fstrim_stamp="${XDG_RUNTIME_DIR:-/tmp}/.dotfiles-fstrim-$(id -u)"
		if [ ! -e "$fstrim_stamp" ]; then
			sudo fstrim / 2>/dev/null
			: >"$fstrim_stamp"
		fi

		if [ "$(findmnt --noheadings -o PROPAGATION / || true)" = "private" ]; then
			sudo mount --make-shared /
		fi

		wsl2_mountpoint="/mnt/wsl/${WSL_DISTRO_NAME}"
		if ! findmnt --mountpoint="$wsl2_mountpoint" >/dev/null; then
			mkdir -p -- "$wsl2_mountpoint"
			sudo mount --bind / "$wsl2_mountpoint"
		fi
		unset wsl2_mountpoint fstrim_stamp
	fi

	if [ -x /usr/bin/gnome-keyring-daemon ] && [ -z "$GNOME_KEYRING_CONTROL" ]; then
		gnome_env="$(/usr/bin/gnome-keyring-daemon --start --components=secrets 2>/dev/null)"
		if [ -n "$gnome_env" ]; then
			eval "$gnome_env"
			export GNOME_KEYRING_CONTROL
		fi
		unset gnome_env
	fi
fi
