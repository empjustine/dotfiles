#!/bin/sh

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
		if [ -x /home/linuxbrew/.linuxbrew/bin/mise ]; then
			eval "$(/home/linuxbrew/.linuxbrew/bin/mise activate bash || true)"
		fi

		if [ -x ~/.local/share/mise/shims/fnox ]; then
			eval "$(~/.local/share/mise/shims/fnox activate bash || true)"
		fi
	fi
elif [ -n "$ZSH_VERSION" ]; then
	bindkey -e

	[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh || true)"

	if [ -n "$PS1" ]; then
		if [ -x /home/linuxbrew/.linuxbrew/bin/mise ]; then
			eval "$(/home/linuxbrew/.linuxbrew/bin/mise activate zsh || true)"
		fi

		autoload -U compinit
		compinit

		#allow tab completion in the middle of a word
		setopt COMPLETE_IN_WORD

		# shellcheck disable=SC1090,SC3001,SC3046
		[ -x ~/.local/share/mise/shims/kubectl ] && source <(~/.local/share/mise/shims/kubectl completion zsh || true)
	fi
fi