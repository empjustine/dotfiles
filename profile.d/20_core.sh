#!/bin/sh

if [ -n "$PS1" ] && [ -n "$BASH_VERSION" ]; then
	PS1='\w\$ '
elif [ -n "$PS1" ] && [ -n "$ZSH_VERSION" ]; then
	PS1='%~%# '
fi

if [ -n "$BASH_VERSION" ]; then
	if [ -r /etc/bashrc ]; then
		. /etc/bashrc
	fi
	if [ -r "${PREFIX}/etc/bash.bashrc" ]; then
		. "${PREFIX}/etc/bash.bashrc"
	fi
fi
