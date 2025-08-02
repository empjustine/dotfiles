#!/bin/bash

if [ -x /home/linuxbrew/.linuxbrew/bin/atuin ]; then
	eval "$(/home/linuxbrew/.linuxbrew/bin/atuin init zsh --disable-up-arrow)"
fi
