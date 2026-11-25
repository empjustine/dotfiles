#!/bin/sh
# wsl-space-reserve.sh — size the WSL ext4 reserve file from host and guest
# free space. WSL-only: needs fallocate, truncate, stat -c, df and /mnt/c.
# Gate: host maintenance; run by hand or from a host tool, never sourced.

set -eu

RESERVE_FILE=${RESERVE_FILE:-"$HOME/reserve/reserve-A"}
GUEST_MOUNT=${GUEST_MOUNT:-/}
HOST_MOUNT=${HOST_MOUNT:-/mnt/c}

MIN_RESERVE_GIB=${MIN_RESERVE_GIB:-8}
RESERVE_PERCENT=${RESERVE_PERCENT:-5}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

case $MIN_RESERVE_GIB in
	'' | *[!0-9]*) die "MIN_RESERVE_GIB must be an integer" ;;
	*) : ;;
esac

case $RESERVE_PERCENT in
	'' | *[!0-9]*) die "RESERVE_PERCENT must be an integer" ;;
	*) : ;;
esac

[ "$RESERVE_PERCENT" -le 100 ] \
	|| die "RESERVE_PERCENT must not exceed 100"

command -v fallocate >/dev/null 2>&1 \
	|| die "fallocate is required"
command -v truncate >/dev/null 2>&1 \
	|| die "truncate is required"

mkdir -p "$(dirname "$RESERVE_FILE")"

if [ ! -e "$RESERVE_FILE" ]; then
	: >"$RESERVE_FILE"
fi

[ -f "$RESERVE_FILE" ] \
	|| die "$RESERVE_FILE is not a regular file"

# Use 1024-byte units throughout. POSIX df -P is specified in 512-byte
# units unless -k is also supplied.
guest_avail_kib=$(
	df -Pk "$GUEST_MOUNT" \
		| awk 'NR == 2 { print $4 }'
)

host_avail_kib=$(
	df -Pk "$HOST_MOUNT" \
		| awk 'NR == 2 { print $4 }'
)

# Validate both sides separately. A single "$guest:$host" pattern misses an
# empty host field (for example when HOST_MOUNT is not mounted).
case $guest_avail_kib in
	'' | *[!0-9]*) die "could not read guest filesystem capacity" ;;
	*) : ;;
esac
case $host_avail_kib in
	'' | *[!0-9]*) die "could not read host filesystem capacity" ;;
	*) : ;;
esac

# stat %b reports allocated 512-byte blocks. This counts fallocate-created
# unwritten extents, unlike stat %s, which is only the logical file length.
reserve_blocks_512=$(stat -c '%b' "$RESERVE_FILE")
reserve_alloc_kib=$(((reserve_blocks_512 + 1) / 2))

minimum_kib=$((MIN_RESERVE_GIB * 1024 * 1024))
percentage_kib=$((host_avail_kib * RESERVE_PERCENT / 100))

if [ "$minimum_kib" -gt "$percentage_kib" ]; then
	safety_kib=$minimum_kib
else
	safety_kib=$percentage_kib
fi

# Maximum amount WSL should be allowed to consume before ext4 returns ENOSPC.
if [ "$host_avail_kib" -gt "$safety_kib" ]; then
	target_guest_avail_kib=$((host_avail_kib - safety_kib))
else
	target_guest_avail_kib=0
fi

# Capacity available if the current reservation did not exist.
unreserved_guest_avail_kib=$((guest_avail_kib + reserve_alloc_kib))

if [ "$unreserved_guest_avail_kib" -gt "$target_guest_avail_kib" ]; then
	target_reserve_kib=$((unreserved_guest_avail_kib - target_guest_avail_kib))
else
	target_reserve_kib=0
fi

printf 'Windows available:            %12s MiB\n' \
	"$((host_avail_kib / 1024))"
printf 'Windows safety margin:        %12s MiB\n' \
	"$((safety_kib / 1024))"
printf 'Target WSL availability:      %12s MiB\n' \
	"$((target_guest_avail_kib / 1024))"
printf 'Current WSL availability:     %12s MiB\n' \
	"$((guest_avail_kib / 1024))"
printf 'Current ext4 reservation:     %12s MiB\n' \
	"$((reserve_alloc_kib / 1024))"
printf 'Target ext4 reservation:      %12s MiB\n' \
	"$((target_reserve_kib / 1024))"

if [ "$target_reserve_kib" -gt "$reserve_alloc_kib" ]; then
	# Set the logical length, then ensure the range has unwritten extents.
	#
	# fallocate -l alone does not shrink an existing file, but it grows and
	# allocates a smaller file to the requested length.
	fallocate -l "${target_reserve_kib}K" "$RESERVE_FILE"

elif [ "$target_reserve_kib" -lt "$reserve_alloc_kib" ]; then
	# Shrinking the file releases ext4 blocks. fallocate -l would not shrink.
	truncate -s "${target_reserve_kib}K" "$RESERVE_FILE"
fi

sync

new_guest_avail_kib=$(
	df -Pk "$GUEST_MOUNT" \
		| awk 'NR == 2 { print $4 }'
)

new_reserve_blocks_512=$(stat -c '%b' "$RESERVE_FILE")
new_reserve_alloc_kib=$(((new_reserve_blocks_512 + 1) / 2))

printf 'Resulting WSL availability:   %12s MiB\n' \
	"$((new_guest_avail_kib / 1024))"
printf 'Resulting ext4 reservation:   %12s MiB\n' \
	"$((new_reserve_alloc_kib / 1024))"

# Allow a small tolerance for filesystem accounting and allocation units.
tolerance_kib=$((16 * 1024))

if [ "$new_guest_avail_kib" -gt \
	$((target_guest_avail_kib + tolerance_kib)) ]; then
	die "WSL availability remains above its calculated safe target"
fi
