#!/usr/bin/env zsh

if [ -n "$PS1" ]; then
	PS1="${PS1//\[%n@%m\]/}"
fi
