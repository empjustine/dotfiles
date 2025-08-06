#!/bin/bash

# brew install atuin bash-preexec
if
	[ -n "$PS1" ] \
		&& [ -x "/home/linuxbrew/.linuxbrew/bin/atuin" ] \
		&& [ -r "/home/linuxbrew/.linuxbrew/etc/profile.d/bash-preexec.sh" ]
then
	eval "$(atuin init bash --disable-up-arrow)"
	. /home/linuxbrew/.linuxbrew/etc/profile.d/bash-preexec.sh
fi
