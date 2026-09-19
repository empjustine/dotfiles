#!/data/data/com.termux/files/usr/bin/sh
#
# Termux:Widget background task — restart the sshd service and toast its
# status (the same script termux-shortcuts.html used to embed). Install
# target: ~/.shortcuts/tasks/sshd.sh; deploy.sh copies this file there,
# chmod 700.
#
# Unlike profile.d/ snippets this is a standalone task script: it is
# never sourced by the profile loop, so it can run commands
# unconditionally. Maintained as a real file (not a heredoc) so lint.sh
# covers it like any other shell script.

# shellcheck source=/dev/null
. ~/dotfiles/src-dotfiles.sh

set -x

#SVDIR=$PREFIX/var/service
SVDIR=/data/data/com.termux/files/usr/var/service
LOGDIR=/data/data/com.termux/files/usr/var/log

export SVDIR
export LOGDIR
sv down sshd
pkill sshd
sv up sshd

termux-toast "$(sv status sshd || true)"
