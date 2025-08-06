#!/bin/bash

if [ -n "$PS1" ]; then
	case "$0" in
		*zsh*) ;;
		*)
			if [ -x /bin/zsh ]; then
				/bin/zsh
			elif [ -x /data/data/com.termux/files/usr/bin/zsh ]; then
				/data/data/com.termux/files/usr/bin/zsh
			fi
			;;
	esac
fi
