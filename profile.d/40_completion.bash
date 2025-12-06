#!/bin/bash

if [ -n "$BASH_VERSION" ]; then
	[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash || true)"

	if [ -n "$PS1" ]; then
		[ -x /etc/profile.d/bash_completion.sh ] && . /etc/profile.d/bash_completion.sh

		if [ -r /home/linuxbrew/.linuxbrew/etc/profile.d/bash_completion.sh ]; then
			. /home/linuxbrew/.linuxbrew/etc/profile.d/bash_completion.sh
		else
			for bash_completion in /home/linuxbrew/.linuxbrew/etc/bash_completion.d/*; do
				if [ -r "$bash_completion" ]; then
					. "$bash_completion"
				fi
			done
			unset bash_completion
		fi

		[ -x /home/linuxbrew/.linuxbrew/bin/mise ] && eval "$(/home/linuxbrew/.linuxbrew/bin/mise activate bash || true)"
		[ -x /home/linuxbrew/.linuxbrew/bin/uv ] && eval "$(/home/linuxbrew/.linuxbrew/bin/uv generate-shell-completion bash || true)"
		[ -x /home/linuxbrew/.linuxbrew/bin/uvx ] && eval "$(/home/linuxbrew/.linuxbrew/bin/uvx --generate-shell-completion bash || true)"
		[ -x ~/.local/share/mise/shims/fnox ] && eval "$(~/.local/share/mise/shims/fnox activate bash || true)"

		if [ -x ~/.local/share/mise/shims/kubectl ]; then
			source <(~/.local/share/mise/shims/kubectl completion bash || true)
		elif [ -x /home/linuxbrew/.linuxbrew/bin/kubectl ]; then
			source <(/home/linuxbrew/.linuxbrew/bin/kubectl completion bash || true)
		fi
	fi
fi
