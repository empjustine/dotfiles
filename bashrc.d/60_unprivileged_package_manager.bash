#!/bin/bash

if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"

	if [ -n "$PS1" ]; then
		#HOMEBREW_PREFIX="$(/home/linuxbrew/.linuxbrew/bin/brew --prefix)"
		if [[ -r "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh" ]]; then
			. "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh"
		else
			for COMPLETION in "${HOMEBREW_PREFIX}/etc/bash_completion.d/"*; do
				[[ -r "${COMPLETION}" ]] && source "${COMPLETION}"
			done
		fi
	fi
fi

if [ -x /home/linuxbrew/.linuxbrew/bin/mise ]; then
	# /home/linuxbrew/.linuxbrew/bin/mise reshim
	if [ -n "$PS1" ]; then
		eval "$(/home/linuxbrew/.linuxbrew/bin/mise activate bash)"
	else
		eval "$(/home/linuxbrew/.linuxbrew/bin/mise activate --shims)"
	fi
fi
