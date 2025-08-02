#!/bin/bash

if [ -n "$PS1" ] && [ -x /bin/zsh ]; then
	/bin/zsh
fi

if [ -n "$PS1" ] && [ -x /data/data/com.termux/files/usr/bin/zsh ]; then
	/data/data/com.termux/files/usr/bin/zsh
fi
