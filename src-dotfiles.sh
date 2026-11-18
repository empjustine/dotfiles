#!/bin/sh
# Unified dotfiles entrypoint: guards, sources lib/dotfiles.sh, then loops
# $DOTFILES/profile.d and sources each snippet. The snippet contract is in
# docs/system.md §4, the expected execution shapes and their costs are in
# docs/execution-map.md, and the documentation contract itself is in
# docs/spec-standard.md.
#
# Snippet extensions: *.sh — POSIX, sourced by every shell (under zsh this
# is wrapped in `emulate -L ksh` so options stay local to the helper while
# the snippet's exports still escape); *.bash — bash-only; *.zsh — zsh-only.
# Shell-generated code (completions, zsh widgets) must never move into *.sh:
# `emulate -L ksh` changes the semantics it runs under (DR-040).
#
# The interpreter may be dash (e.g. /etc/profile.d deployment), so *.sh
# snippets must stay POSIX-clean (no [[, <(...), no `local`, no `source`).

# Re-entrancy guard (DR-027). Termux's $PREFIX/etc/profile sources ~/.bashrc
# itself, and 20_core.bash sources that same profile for non-login shells —
# without this check the chain recurses (bashrc → 20_core → /etc/profile →
# bashrc → …); bash login also reads ~/.bash_profile after /etc/profile, so
# snippets would otherwise run twice.
# DOTFILES_SOURCED is deliberately NOT unset or exported: it must survive
# across all rc files sourced within one shell process, while child shells
# (nested bash, ssh, tmux panes) are new processes and must install their
# own hooks.
# shellcheck disable=SC2317  # `exit 0` only fires when executed, not sourced
if [ -n "$DOTFILES_SOURCED" ]; then
	return 0 2>/dev/null || exit 0
fi

# Set BEFORE the loop: the loop re-enters this file (20_core sources
# /etc/profile, which sources ~/.bashrc again on Termux login shells), so
# the guard must already be up when that inner source arrives.
DOTFILES_SOURCED=1

_src_one() {
	rc="$1"
	[ -r "$rc" ] || return 0
	case "$rc" in
		*.sh)
			if [ -n "$ZSH_VERSION" ]; then
				emulate -L ksh
			fi
			# shellcheck source=/dev/null
			. "$rc"
			;;
		*.bash)
			# shellcheck disable=SC1090
			[ -n "$BASH_VERSION" ] && . "$rc"
			;;
		*.zsh)
			# shellcheck disable=SC1090
			[ -n "$ZSH_VERSION" ] && . "$rc"
			;;
		# Unknown extensions are skipped silently, by design.
		*) : ;;
	esac
}

# Shared helpers first (DR-043): the run-guard the throttled snippets need.
# Optional by construction — a checkout without lib/ still runs, minus the
# throttles, and every caller guards on the helper being defined.
_df_lib="${DOTFILES:-$HOME/dotfiles}/lib/dotfiles.sh"
if [ -r "$_df_lib" ]; then
	# shellcheck source=/dev/null
	. "$_df_lib"
fi
unset _df_lib

for rc in "${DOTFILES:-$HOME/dotfiles}/profile.d/"*; do
	_src_one "$rc"
done

unset -f _src_one
unset rc
