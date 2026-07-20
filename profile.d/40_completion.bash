#!/bin/bash

if [ -n "$BASH_VERSION" ]; then
	[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash || true)"

	if [ -n "$PS1" ]; then
		if [ -x /etc/profile.d/bash_completion.sh ]; then
			# shellcheck source=/dev/null
			. /etc/profile.d/bash_completion.sh
		fi

		if [ -r /home/linuxbrew/.linuxbrew/etc/profile.d/bash_completion.sh ]; then
			# shellcheck source=/dev/null
			. /home/linuxbrew/.linuxbrew/etc/profile.d/bash_completion.sh
		else
			for bash_completion in /home/linuxbrew/.linuxbrew/etc/bash_completion.d/*; do
				if [ -r "$bash_completion" ]; then
					# shellcheck source=/dev/null
					. "$bash_completion"
				fi
			done
			unset bash_completion
		fi

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
		[ -n "$mise_bin" ] && eval "$("$mise_bin" activate bash || true)"

		uv_bin="$(_dotfiles_tool uv)"
		[ -n "$uv_bin" ] && eval "$("$uv_bin" generate-shell-completion bash || true)"

		uvx_bin="$(_dotfiles_tool uvx)"
		[ -n "$uvx_bin" ] && eval "$("$uvx_bin" --generate-shell-completion bash || true)"

		fnox_bin="$(_dotfiles_tool fnox)"
		[ -n "$fnox_bin" ] && eval "$("$fnox_bin" activate bash || true)"

		kubectl_bin="$(_dotfiles_tool kubectl)"
		[ -n "$kubectl_bin" ] && source <("$kubectl_bin" completion bash || true)

		unset mise_bin uv_bin uvx_bin fnox_bin kubectl_bin _dotfiles_tool _dotfiles_mise
	fi
else
	printf '%s\n' "dotfiles: bash-only snippet sourced under a non-bash shell; skipping" >&2
fi
