#1/bin/sh

if [ -n "$PS1" ] && [ -n "$BASH_VERSION" ]; then
	PS1='\w\$ '
elif [ -n "$PS1" ] && [ -n "$ZSH_VERSION" ]; then
	PS1='%~%# '
fi

if [ -n "$BASH_VERSION" ]; then
	if [ -r /etc/bashrc ]; then
		. /etc/bashrc
	elif [ -r "${PREFIX}/etc/bash.bashrc" ]; then
		. "${PREFIX}/etc/bash.bashrc"
	fi
fi

if [ -d "${HOME}/.local/bin" ]; then
	PATH="${HOME}/.local/bin:${PATH}"
fi
if [ -d /run/media/yoomuin/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/var/home/deck/bin/ ]; then
	PATH="/run/media/yoomuin/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/var/home/deck/bin/:${PATH}"
fi
