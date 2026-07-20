#!/bin/zsh

if [ -n "$ZSH_VERSION" ]; then
	bindkey -e

	if [ -n "$PS1" ]; then
		autoload -U compinit
		compinit
		setopt COMPLETE_IN_WORD

		[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh || true)"

		# Discover CLI tools via an allowlist cascade, then wire up completions.
		# Per-tool cascade: mise user shim -> system mise shim -> brew -> system.
		# `mise` itself uses the shorter brew -> system cascade.
		_dotfiles_tool() {
			local _name="$1" _c
			for _c in \
				"$HOME/.local/share/mise/shims/$_name" \
				"${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims/$_name" \
				"${MISE_SYSTEM_DATA_DIR:-/usr/local/share/mise}/shims/$_name" \
				/usr/local/share/mise/shims/$_name \
				/home/linuxbrew/.linuxbrew/bin/$_name \
				/usr/bin/$_name ; do
				[ -x "$_c" ] && { printf '%s' "$_c"; return 0; }
			done
			return 1
		}
		_dotfiles_mise() {
			local _c
			for _c in \
				/home/linuxbrew/.linuxbrew/bin/mise \
				/usr/bin/mise ; do
				[ -x "$_c" ] && { printf '%s' "$_c"; return 0; }
			done
			return 1
		}

		mise_bin="$(_dotfiles_mise)"
		[ -n "$mise_bin" ] && eval "$("$mise_bin" activate zsh || true)"

		uv_bin="$(_dotfiles_tool uv)"
		[ -n "$uv_bin" ] && eval "$("$uv_bin" generate-shell-completion zsh || true)"

		uvx_bin="$(_dotfiles_tool uvx)"
		[ -n "$uvx_bin" ] && eval "$("$uvx_bin" --generate-shell-completion zsh || true)"

		kubectl_bin="$(_dotfiles_tool kubectl)"
		[ -n "$kubectl_bin" ] && source <("$kubectl_bin" completion zsh || true)

		unset mise_bin uv_bin uvx_bin kubectl_bin _dotfiles_tool _dotfiles_mise
	fi
else
	printf '%s\n' "dotfiles: zsh-only snippet sourced under a non-zsh shell; skipping" >&2
fi
