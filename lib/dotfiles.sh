#!/bin/sh
# Shared helpers for the profile.d/ snippets (DR-043). Sourced once by
# src-dotfiles.sh, before the snippet loop, and read by shell-specific files
# too — so it must stay POSIX/dash-clean (DR-002). Nothing here runs on its
# own.
#
# The run-guard exists because some work must happen 'every N shell startups or
# every X seconds', never on every shell start (REQ-8/NFR-7): generating the
# completion blobs is its first user (DR-041, 40_completion.*). The state lives
# outside the shell in $XDG_STATE_HOME, so the counting survives across
# processes — which is the whole point.
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
		# shellcheck disable=SC3028  # zsh: EPOCHSECONDS comes from zsh/datetime
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
