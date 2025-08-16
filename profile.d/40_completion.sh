#!/bin/sh

if [ -n "$ZSH_VERSION" ]; then
	bindkey -e

	[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh || true)"

	if [ -x /home/linuxbrew/.linuxbrew/bin/mise ]; then
		/home/linuxbrew/.linuxbrew/bin/mise reshim
		if [ -n "$PS1" ]; then
			eval "$(/home/linuxbrew/.linuxbrew/bin/mise activate zsh || true)"
		else
			eval "$(/home/linuxbrew/.linuxbrew/bin/mise activate --shims || true)"
		fi
	fi

	if [ -n "$PS1" ]; then
		autoload -U compinit
        	compinit

        	#allow tab completion in the middle of a word
        	setopt COMPLETE_IN_WORD

        	# shellcheck disable=SC1090,SC3001,SC3046
        	[ -x ~/.local/share/mise/shims/kubectl ] && source <(~/.local/share/mise/shims/kubectl completion zsh || true)
	fi
elif [ -n "$BASH_VERSION" ]; then
	[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash || true)"

	if [ -n "$PS1" ]; then
		[ -x /etc/profile.d/bash_completion.sh ] && . /etc/profile.d/bash_completion.sh

		if [ -r /home/linuxbrew/.linuxbrew/etc/profile.d/bash_completion.sh ]; then
			. /home/linuxbrew/.linuxbrew/etc/profile.d/bash_completion.sh
		else
			for COMPLETION in /home/linuxbrew/.linuxbrew/etc/bash_completion.d/*; do
				if [ -r "$COMPLETION" ]; then
					. "$COMPLETION"
				fi
			done
		fi
	fi

	if [ -x /home/linuxbrew/.linuxbrew/bin/mise ]; then
		/home/linuxbrew/.linuxbrew/bin/mise reshim
		if [ -n "$PS1" ]; then
			eval "$(/home/linuxbrew/.linuxbrew/bin/mise activate bash || true)"
		else
			eval "$(/home/linuxbrew/.linuxbrew/bin/mise activate --shims || true)"
		fi
	fi
fi