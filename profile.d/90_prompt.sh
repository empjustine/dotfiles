#!/bin/bash

if [ -n "$PS1" ] && [ -n "$BASH_VERSION" ]; then
	PS1='\w\$ '
elif [ -n "$PS1" ] && [ -n "$ZSH_VERSION" ]; then
	PS1='%~%# '
fi
