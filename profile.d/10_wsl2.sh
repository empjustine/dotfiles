#!/bin/sh
# 10_wsl2.sh — WSL2 plumbing (DR-007, DR-017, DR-038).
#
# Gate: $WSL_DISTRO_NAME, then case "$-" — everything privileged is
# interactive-only. Does: XDG_RUNTIME_DIR slash strip (always); per boot:
# tmpfs ownership, fstrim, shared-root propagation, /mnt/wsl bind; then the
# keyring bootstrap. Throttle: one per-boot stamp (docs/execution-map.md §4).

if [ -n "$WSL_DISTRO_NAME" ]; then

	# normal linux: printenv XDG_RUNTIME_DIR
	# /run/user/1000
	# wsl2: printenv XDG_RUNTIME_DIR
	# /run/user/1000/
	XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR%/}"

	# Interactive-only, canonical guard (DR-017: `$-` carries `i`). Covers
	# the keyring too: no non-interactive session (ssh host cmd, scp, CI)
	# needs a Secret Service provider, and every step below can fork sudo.
	case "$-" in
		*i*) ;;
		*) return 0 ;;
	esac

	# Everything privileged is gated by ONE per-boot stamp. The steps are
	# idempotent probes, but each one forks (sudo ~9ms, findmnt ~2ms) and
	# there is nothing to repair between boots — so per boot is the right
	# granularity, not per interactive shell (DR-038). boot_id in the name
	# keeps a /tmp fallback from looking like this boot's stamp. The stamp
	# subsumes the old standalone fstrim stamp: same lifetime.
	# uid/gid once: these feed the stamp name and both privileged calls, and
	# command substitution inside an argument makes the exit status opaque
	# (shellcheck SC2312).
	df_uid="$(id -u)"
	df_gid="$(id -g)"
	read -r df_boot_id </proc/sys/kernel/random/boot_id || df_boot_id=na
	df_boot_stamp="${XDG_RUNTIME_DIR:-/tmp}/.dotfiles-wsl-${df_boot_id}-${df_uid}"
	if [ ! -e "$df_boot_stamp" ]; then
		sudo mkdir -p -- "/run/user/$df_uid" "$XDG_RUNTIME_DIR"
		sudo chown "$df_uid:$df_gid" -- "/run/user/$df_uid" "$XDG_RUNTIME_DIR"

		# fstrim is heavy and already handled by systemd timers: once per boot
		# just tops it up.
		sudo fstrim / 2>/dev/null

		# Rootless Podman needs a shared root propagation mount.
		if [ "$(findmnt --noheadings -o PROPAGATION / || true)" = "private" ]; then
			sudo mount --make-shared /
		fi

		# Bind / into WSL2's shared /mnt/wsl namespace so other distros reach
		# this filesystem directly instead of round-tripping via DrvFS/9p.
		df_wsl_mountpoint="/mnt/wsl/${WSL_DISTRO_NAME}"
		if ! findmnt --mountpoint="$df_wsl_mountpoint" >/dev/null; then
			mkdir -p -- "$df_wsl_mountpoint"
			sudo mount --bind / "$df_wsl_mountpoint"
		fi
		unset df_wsl_mountpoint
		: >"$df_boot_stamp"
	fi
	unset df_uid df_gid df_boot_id df_boot_stamp

	# Bootstrap a Secret Service (libsecret) provider without a desktop
	# session. Started only once per session (the env it prints is what
	# later shells need) and only when nothing is running.
	if [ -x /usr/bin/gnome-keyring-daemon ] && [ -z "$GNOME_KEYRING_CONTROL" ]; then
		gnome_env="$(/usr/bin/gnome-keyring-daemon --start --components=secrets 2>/dev/null)"
		if [ -n "$gnome_env" ]; then
			eval "$gnome_env"
			export GNOME_KEYRING_CONTROL
		fi
		unset gnome_env
	fi
fi
