#!/data/data/com.termux/files/usr/bin/sh
#
# Termux:Widget background task — refresh the LAN-IP JSON for Markor and
# toast the primary IPv4. Install target: ~/.shortcuts/tasks/ip.sh;
# deploy.sh copies this file there, chmod 700.
#
# Bundles profile.d/50_ip.sh's logic minus the interactive-only guard:
# the widget spawns non-interactive shells, where the guard would
# otherwise skip the write. Standalone task script contract: see
# shortcuts/tasks/sshd.sh.

# shellcheck source=/dev/null
. ~/dotfiles/src-dotfiles.sh

if [ -d ~/storage/shared/Documents/markor ]; then
	ip --json addr >~/storage/shared/Documents/markor/ip.json
fi

# Toast a usable response: the primary IPv4 (the first inet address on
# wlan0), which the JSON's full dump is not. jq is preferred; fall back
# to awk when missing.
ip4=$(ip --json addr show dev wlan0 2>/dev/null | jq -r '.[0].addr_info[] | select(.family == "inet") | .local' 2>/dev/null | head -1)
if [ -z "$ip4" ]; then
	ip4=$(ip -4 addr show dev wlan0 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)
fi
if [ -n "$ip4" ]; then
	termux-toast "wlan0: $ip4"
else
	termux-toast "ip.json updated"
fi
