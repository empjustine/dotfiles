#!/bin/zsh

if [ -n "$ZSH_VERSION" ]; then
	bindkey -e

	if [ -n "$PS1" ]; then
		autoload -U compinit
		compinit
		setopt COMPLETE_IN_WORD

		[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh || true)"
		[ -x /home/linuxbrew/.linuxbrew/bin/mise ] && eval "$(/home/linuxbrew/.linuxbrew/bin/mise activate zsh || true)"
		[ -x /home/linuxbrew/.linuxbrew/bin/uv ] && eval "$(/home/linuxbrew/.linuxbrew/bin/uv generate-shell-completion zsh || true)"
		[ -x /home/linuxbrew/.linuxbrew/bin/uvx ] && eval "$(/home/linuxbrew/.linuxbrew/bin/uvx --generate-shell-completion zsh || true)"

		if [ -x ~/.local/share/mise/shims/kubectl ]; then
			source <(~/.local/share/mise/shims/kubectl completion zsh || true)
		elif [ -x /home/linuxbrew/.linuxbrew/bin/kubectl ]; then
			source <(/home/linuxbrew/.linuxbrew/bin/kubectl completion zsh || true)
		fi
	fi
fi
