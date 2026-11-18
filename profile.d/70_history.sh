#!/bin/sh

df_state="${XDG_STATE_HOME:-$HOME/.local/state}"
df_config="${XDG_CONFIG_HOME:-$HOME/.config}"

# mkdir only when the dir is actually missing: steady state is two in-shell
# `-d` tests (no fork) instead of two `mkdir -p` forks (~1.5ms) per shell,
# and it still repairs a deleted dir (DR-038). No throttle stamp: this has
# to stay self-healing rather than "runs on the Nth shell".
[ -d "$df_config/vim" ] || mkdir -p -- "$df_config/vim"
[ -d "$df_state" ] || mkdir -p -- "$df_state"

DUCKDB_HISTORY="$df_state/duckdb_history"
export DUCKDB_HISTORY

NODE_REPL_HISTORY="$df_state/node_repl_history"
NODE_REPL_HISTORY_SIZE=10000
export NODE_REPL_HISTORY NODE_REPL_HISTORY_SIZE

SQLITE_HISTORY="$df_state/sqlite_history"
export SQLITE_HISTORY

# Added in version 3.13.
# https://docs.python.org/3/using/cmdline.html#envvar-PYTHON_HISTORY
# PYTHON_HISTORY="$df_state/python_history"

merge_history() {
	default="$1"
	target="$2"
	if [ -r "$default" ] && [ "$default" != "$target" ]; then
		# >/dev/null: tee mirrors stdin to stdout, which at login would dump
		# the whole legacy history file into the terminal.
		tee -a -- "$target" >/dev/null <"$default"
		rm "$default"
	fi
}

merge_history ~/.duckdb_history "$DUCKDB_HISTORY"
merge_history ~/.node_repl_history "$NODE_REPL_HISTORY"
merge_history ~/.sqlite_history "$SQLITE_HISTORY"
# `unset -f`: a plain `unset` does not remove functions in zsh (and this file
# is sourced under zsh too, DR-003).
unset -f merge_history
unset default target df_state df_config
