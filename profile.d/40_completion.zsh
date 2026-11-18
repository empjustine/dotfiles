#!/bin/zsh

[ -n "$ZSH_VERSION" ] || { printf '%s\n' "dotfiles: zsh-only snippet sourced under a non-zsh shell; skipping" >&2; return 0; }

bindkey -e

case "$-" in
	*i*) ;;
	*) return 0 ;;
esac

autoload -U compinit
compinit
setopt COMPLETE_IN_WORD

[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh || true)"

# Allowlist cascade (DR-016: an arbitrary $PATH lookup is never trusted).
# Candidate list and trust gate are identical in 40_completion.bash and
# 40_completion.zsh — they must stay identical.
_dotfiles_tool() {
	local _name="$1" _c
	for _c in \
		"$HOME/.local/share/mise/shims/$_name" \
		"${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims/$_name" \
		"${MISE_SYSTEM_DATA_DIR:-/usr/local/share/mise}/shims/$_name" \
		/usr/local/share/mise/shims/$_name \
		/home/linuxbrew/.linuxbrew/bin/$_name \
		/usr/bin/$_name; do
		[ -x "$_c" ] || continue
		# A mise shim only works while the mise binary itself is resolvable.
		# If it isn't, selecting the shim would run a broken binary and shadow
		# later candidates — skip instead (DR-026). Resolvable means: on
		# $PATH, or found by the allowlisted _dotfiles_mise probe below (this
		# snippet runs before 80_path.sh, so a fresh login may have neither a
		# PATH entry nor a brew/system mise — DR-034).
		case "$_c" in
			*/mise/shims/*) { command -v mise >/dev/null 2>&1 || [ -n "$mise_bin" ]; } || continue ;;
			*) : ;;
		esac
		printf '%s' "$_c"
		return 0
	done
	return 1
}

_dotfiles_mise() {
	local _c
	for _c in \
		"$HOME/.local/bin/mise" \
		"${XDG_DATA_HOME:-$HOME/.local/share}/mise/bin/mise" \
		/home/linuxbrew/.linuxbrew/bin/mise \
		/usr/bin/mise; do
		if [ -x "$_c" ]; then
			printf '%s' "$_c"
			return 0
		fi
	done
	return 1
}

mise_bin="$(_dotfiles_mise)"
[ -n "$mise_bin" ] && eval "$($mise_bin activate zsh || true)"

uv_bin="$(_dotfiles_tool uv)"
[ -n "$uv_bin" ] && eval "$($uv_bin generate-shell-completion zsh || true)"

uvx_bin="$(_dotfiles_tool uvx)"
[ -n "$uvx_bin" ] && eval "$($uvx_bin --generate-shell-completion zsh || true)"

kubectl_bin="$(_dotfiles_tool kubectl)"
[ -n "$kubectl_bin" ] && eval "$($kubectl_bin completion zsh || true)"

# zsh: plain `unset` only removes *parameters* — the helpers are functions, so
# they need `-f` or they leak into the interactive shell (verified 2026-11-18).
unset mise_bin uv_bin uvx_bin kubectl_bin
unset -f _dotfiles_tool _dotfiles_mise
