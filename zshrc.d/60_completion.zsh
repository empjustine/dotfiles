#!/usr/bin/env zsh

if [ -x ~/.local/share/mise/shims/kubectl ]; then
	source <(~/.local/share/mise/shims/kubectl completion zsh)
fi
