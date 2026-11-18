#!/bin/bash
# 40_completion.bash — tab completion for interactive bash (DR-017, DR-018).
#
# What it does: brew shellenv, the bash-completion framework, and completions
# for mise/uv/uvx/kubectl. The generated blobs are NOT eval'd on shell start:
# they are written to $XDG_CACHE_HOME/dotfiles/completions behind the run-guard
# (lib/dotfiles.sh, DR-043) and sourced by a self-replacing `complete -F` stub
# on the first TAB that needs them (DR-041). Shell start pays for discovery and
# three `complete` builtins instead of four generator processes.
#
# Gate: bash only, interactive only. Side effects: PATH (brew), the completion
# cache directory, and in-shell completer registrations.

[ -n "$BASH_VERSION" ] || {
	printf '%s\n' "dotfiles: bash-only snippet sourced under a non-bash shell; skipping" >&2
	return 0
}

[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash || true)"

case "$-" in
	*i*) ;;
	*) return 0 ;;
esac

# The framework file is sourced, not executed: distro packages install it
# non-executable (0644), so probe -r. Eager on purpose — it *is* the framework.
if [ -r /etc/profile.d/bash_completion.sh ]; then
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
# --- lazy, cached completions (DR-041) -------------------------------------
# `complete -F _df_lazy_comp <tool>` stays registered until a TAB needs it. The
# stub then sources the cached blob — which replaces its own registration with
# the real completer — and dispatches to that completer, so the TAB that paid
# for the load still completes.
_df_lazy_comp() {
	local _dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/completions" _reg _fn
	[ -r "$_dir/$1.bash" ] || return 0
	# shellcheck source=/dev/null
	. "$_dir/$1.bash"
	_reg=$(complete -p "$1" 2>/dev/null) || return 0
	_fn=${_reg##*-F }
	_fn=${_fn%% *}
	[ "$_fn" = _df_lazy_comp ] && return 0
	"$_fn" "$@"
}

_df_cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/completions"
_df_refresh=0
if command -v df_due >/dev/null 2>&1; then
	df_startup
	df_due completions && _df_refresh=1
fi
[ -d "$_df_cache" ] || mkdir -p -- "$_df_cache"

# `mise activate` is the one eager generator left (DR-041 kept it: it is a hook,
# not a completion). Profiled 2026-11-18 (DR-045): ~27 ms net in bash, of which
# ~5 ms is the spawn, ~5 ms the 201-line blob and ~16 ms an inline
# `mise hook-env` — the same call the prompt makes before every command. With
# DOTFILES_MISE_SHIMS=1 the blob is a single PATH export (~7 ms) and the
# per-prompt hook disappears, at the cost of per-directory tool switching.
mise_bin="$(_dotfiles_mise)"
if [ -n "$mise_bin" ]; then
	if [ "${DOTFILES_MISE_SHIMS:-0}" = 1 ]; then
		eval "$($mise_bin activate bash --shims || true)"
	else
		eval "$($mise_bin activate bash || true)"
	fi
fi

# Refresh policy: the run-guard (every N startups or X seconds), a missing blob,
# or a tool binary newer than its blob. A skipped refresh costs two -e/-nt
# builtins per tool and nothing else.
uv_bin="$(_dotfiles_tool uv)"
if [ -n "$uv_bin" ]; then
	_df_blob="$_df_cache/uv.bash"
	if [ "$_df_refresh" = 1 ] || [ ! -e "$_df_blob" ] || [ "$uv_bin" -nt "$_df_blob" ]; then
		if "$uv_bin" generate-shell-completion bash >|"$_df_blob.tmp" 2>/dev/null; then
			mv -f -- "$_df_blob.tmp" "$_df_blob"
		else
			rm -f -- "$_df_blob.tmp"
		fi
	fi
	[ -e "$_df_blob" ] && complete -o bashdefault -o default -o nosort -F _df_lazy_comp uv
fi

uvx_bin="$(_dotfiles_tool uvx)"
if [ -n "$uvx_bin" ]; then
	_df_blob="$_df_cache/uvx.bash"
	if [ "$_df_refresh" = 1 ] || [ ! -e "$_df_blob" ] || [ "$uvx_bin" -nt "$_df_blob" ]; then
		if "$uvx_bin" --generate-shell-completion bash >|"$_df_blob.tmp" 2>/dev/null; then
			mv -f -- "$_df_blob.tmp" "$_df_blob"
		else
			rm -f -- "$_df_blob.tmp"
		fi
	fi
	[ -e "$_df_blob" ] && complete -o bashdefault -o default -o nosort -F _df_lazy_comp uvx
fi

kubectl_bin="$(_dotfiles_tool kubectl)"
if [ -n "$kubectl_bin" ]; then
	_df_blob="$_df_cache/kubectl.bash"
	if [ "$_df_refresh" = 1 ] || [ ! -e "$_df_blob" ] || [ "$kubectl_bin" -nt "$_df_blob" ]; then
		if "$kubectl_bin" completion bash >|"$_df_blob.tmp" 2>/dev/null; then
			mv -f -- "$_df_blob.tmp" "$_df_blob"
		else
			rm -f -- "$_df_blob.tmp"
		fi
	fi
	[ -e "$_df_blob" ] && complete -o bashdefault -o default -o nosort -F _df_lazy_comp kubectl
fi

if [ "$_df_refresh" = 1 ] && command -v df_stamp >/dev/null 2>&1; then
	df_stamp completions
fi

unset _df_cache _df_refresh _df_blob uv_bin uvx_bin kubectl_bin mise_bin
unset -f _dotfiles_tool _dotfiles_mise
