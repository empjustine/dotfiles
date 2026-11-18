#!/bin/sh
# Unified dotfiles entrypoint: guard, run-guard helpers, then the profile.d/
# loop. The snippet contract is in docs/system.md §4, the expected execution
# shapes and their costs are in docs/execution-map.md, and the documentation
# contract itself is in docs/spec-standard.md.
#
# Snippet extensions: *.sh — POSIX, sourced by every shell (under zsh this
# is wrapped in `emulate -L ksh` so options stay local to the helper while
# the snippet's exports still escape); *.bash — bash-only; *.zsh — zsh-only.
# Shell-generated code (completions, zsh widgets) must never move into *.sh:
# `emulate -L ksh` changes the semantics it runs under (DR-040).
#
# The interpreter may be dash (e.g. /etc/profile.d deployment), so this file
# and the *.sh snippets must stay POSIX-clean (no [[, <(...), no `local`).
#
# This file is copied verbatim onto every rc target by deploy.sh and must stay
# self-contained: the helpers below live here, not in a separate library
# (DR-043), so the copy is the whole implementation.

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

# --- run-guard (DR-043) ------------------------------------------------------
# Work that must happen "every N shell startups or every X seconds" — never on
# every shell — asks df_due before doing anything expensive; the first user is
# the completion cache (40_completion.*, DR-041). State lives outside the shell
# in $XDG_STATE_HOME, because counting has to survive across processes.
#
#   df_startup                 count this shell once (interactive callers only)
#   df_due NAME [runs] [secs]  0 = due now, 1 = not due (0 disables a leg)
#   df_stamp NAME              record that NAME ran
#
# Defaults: DOTFILES_RUN_EVERY=50 startups, DOTFILES_RUN_AGE=86400 seconds;
# both are overridable per call site and from the environment.

DF_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"

# Current time without forking where the shell can do it: zsh needs the
# datetime module, bash >= 4.2 has %(%s)T. Only dash (the /etc/profile.d case,
# which never calls the guard) pays for a date(1) fork.
df_now() {
	if [ -n "$ZSH_VERSION" ]; then
		zmodload zsh/datetime 2>/dev/null || :
		# shellcheck disable=SC3028  # zsh: EPOCHSECONDS from zsh/datetime
		DF_NOW="${EPOCHSECONDS:-0}"
	elif [ -n "$BASH_VERSION" ]; then
		# shellcheck disable=SC3045  # bash: printf -v is a builtin, no fork
		printf -v DF_NOW '%(%s)T' -1
	else
		DF_NOW=$(date +%s 2>/dev/null || echo 0)
	fi
}

df_startup() {
	[ -n "$DF_STARTUP" ] && return 0
	_df_seen=0
	if [ -r "$DF_STATE/startups" ]; then
		read -r _df_seen <"$DF_STATE/startups" || :
	fi
	case "$_df_seen" in
		'' | *[!0-9]*) _df_seen=0 ;;
		*) : ;;
	esac
	DF_STARTUP=$((_df_seen + 1))
	[ -d "$DF_STATE" ] || mkdir -p -- "$DF_STATE"
	printf '%s\n' "$DF_STARTUP" >"$DF_STATE/startups"
	unset _df_seen
}

df_due() {
	_df_runs="${2:-${DOTFILES_RUN_EVERY:-50}}"
	_df_secs="${3:-${DOTFILES_RUN_AGE:-86400}}"
	_df_file="$DF_STATE/stamps/$1"
	if [ ! -e "$_df_file" ]; then
		unset _df_runs _df_secs _df_file
		return 0
	fi
	_df_seen=0
	_df_at=0
	read -r _df_seen _df_at <"$_df_file" 2>/dev/null || :
	case "$_df_seen" in '' | *[!0-9]*) _df_seen=0 ;; *) : ;; esac
	case "$_df_at" in '' | *[!0-9]*) _df_at=0 ;; *) : ;; esac
	_df_go=1
	if [ "$_df_runs" -gt 0 ] && [ "${DF_STARTUP:-0}" -gt 0 ] \
		&& [ $((DF_STARTUP - _df_seen)) -ge "$_df_runs" ]; then
		_df_go=0
	fi
	if [ "$_df_go" = 1 ] && [ "$_df_secs" -gt 0 ]; then
		df_now
		[ $((DF_NOW - _df_at)) -ge "$_df_secs" ] && _df_go=0
	fi
	unset _df_runs _df_secs _df_file _df_seen _df_at DF_NOW
	return "$_df_go"
}

df_stamp() {
	[ -n "${DF_STARTUP:-}" ] || df_startup
	df_now
	mkdir -p -- "$DF_STATE/stamps"
	printf '%s %s\n' "${DF_STARTUP:-0}" "${DF_NOW:-0}" >"$DF_STATE/stamps/$1"
	unset DF_NOW
}

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

for rc in "${DOTFILES:-$HOME/dotfiles}/profile.d/"*; do
	_src_one "$rc"
done

unset -f _src_one
unset rc
