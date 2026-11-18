#!/bin/zsh
# 40_completion.zsh — tab completion for interactive zsh (DR-017, DR-018).
#
# What it does: brew shellenv, compinit, and completions for mise/uv/uvx/kubectl.
# The uv/uvx/kubectl generators emit `#compdef` files, which is zsh's own lazy
# mechanism: they are written into a $fpath directory behind the run-guard
# (lib/dotfiles.sh, DR-043) and autoloaded by compinit on the first TAB that
# needs them, so a shell start never evals a completion blob (DR-041).
# `mise activate` stays eager — it is a hook, not a completion.
#
# Gate: zsh only, interactive only. Side effects: PATH (brew), the
# site-functions directory, compdump.

[ -n "$ZSH_VERSION" ] || { printf '%s\n' "dotfiles: zsh-only snippet sourced under a non-zsh shell; skipping" >&2; return 0; }

bindkey -e

case "$-" in
	*i*) ;;
	*) return 0 ;;
esac

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
# --- completions via $fpath (DR-041) ----------------------------------------
# The generated #compdef files are the autoload stubs: write them once (guarded),
# then let compinit pick them up. `_df_zfuncs` comes first in fpath so it wins
# over any stale copy a distro package left behind.
_df_zfuncs="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
[ -d "$_df_zfuncs" ] || mkdir -p -- "$_df_zfuncs"
fpath=("$_df_zfuncs" $fpath)

_df_refresh=0
if command -v df_due >/dev/null 2>&1; then
	df_startup
	df_due completions && _df_refresh=1
fi

mise_bin="$(_dotfiles_mise)"
[ -n "$mise_bin" ] && eval "$($mise_bin activate zsh || true)"

# Refresh policy: the run-guard (every N startups or X seconds), a missing file,
# or a tool binary newer than its file. A skipped refresh costs two -e/-nt
# builtins per tool and nothing else.
uv_bin="$(_dotfiles_tool uv)"
if [ -n "$uv_bin" ]; then
	_df_file="$_df_zfuncs/_uv"
	if [ "$_df_refresh" = 1 ] || [ ! -e "$_df_file" ] || [ "$uv_bin" -nt "$_df_file" ]; then
		if "$uv_bin" generate-shell-completion zsh >|"$_df_file.tmp" 2>/dev/null; then
			mv -f -- "$_df_file.tmp" "$_df_file"
		else
			rm -f -- "$_df_file.tmp"
		fi
	fi
fi

uvx_bin="$(_dotfiles_tool uvx)"
if [ -n "$uvx_bin" ]; then
	_df_file="$_df_zfuncs/_uvx"
	if [ "$_df_refresh" = 1 ] || [ ! -e "$_df_file" ] || [ "$uvx_bin" -nt "$_df_file" ]; then
		if "$uvx_bin" --generate-shell-completion zsh >|"$_df_file.tmp" 2>/dev/null; then
			mv -f -- "$_df_file.tmp" "$_df_file"
		else
			rm -f -- "$_df_file.tmp"
		fi
	fi
fi

kubectl_bin="$(_dotfiles_tool kubectl)"
if [ -n "$kubectl_bin" ]; then
	_df_file="$_df_zfuncs/_kubectl"
	if [ "$_df_refresh" = 1 ] || [ ! -e "$_df_file" ] || [ "$kubectl_bin" -nt "$_df_file" ]; then
		if "$kubectl_bin" completion zsh >|"$_df_file.tmp" 2>/dev/null; then
			mv -f -- "$_df_file.tmp" "$_df_file"
		else
			rm -f -- "$_df_file.tmp"
		fi
	fi
fi

if [ "$_df_refresh" = 1 ] && command -v df_stamp >/dev/null 2>&1; then
	df_stamp completions
fi

# compinit runs after the writes: it reads the #compdef lines from fpath now,
# and the function bodies load on the first completion that needs them.
autoload -U compinit
compinit
setopt COMPLETE_IN_WORD

unset _df_zfuncs _df_refresh _df_file uv_bin uvx_bin kubectl_bin mise_bin
unset -f _dotfiles_tool _dotfiles_mise