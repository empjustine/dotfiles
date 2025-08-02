#!/bin/bash

if [ -x /home/linuxbrew/.linuxbrew/bin/atuin ]; then
	eval "$(/home/linuxbrew/.linuxbrew/bin/atuin init zsh --disable-up-arrow)"
fi

if [ -x /data/data/com.termux/files/usr/bin/atuin ]; then
	eval "$(/data/data/com.termux/files/usr/bin/atuin init zsh --disable-up-arrow)"
fi
