#!/bin/sh

mkdir -p -- "${XDG_CONFIG_HOME:-$HOME/.config}/vim" "${XDG_STATE_HOME:-$HOME/.local/state}"

DUCKDB_HISTORY="${XDG_STATE_HOME:-$HOME/.local/state}/duckdb_history"
export DUCKDB_HISTORY

NODE_REPL_HISTORY="${XDG_STATE_HOME:-$HOME/.local/state}/node_repl_history"
NODE_REPL_HISTORY_SIZE=10000
export NODE_REPL_HISTORY NODE_REPL_HISTORY_SIZE

SQLITE_HISTORY="${XDG_STATE_HOME:-$HOME/.local/state}/sqlite_history"
export SQLITE_HISTORY

# Added in version 3.13.
# https://docs.python.org/3/using/cmdline.html#envvar-PYTHON_HISTORY
# PYTHON_HISTORY="${XDG_STATE_HOME:-$HOME/.local/state}/python_history"

merge_history() {
	default="$1"
	target="$2"
	if [ -r "$default" ] && [ "$default" != "$target" ]; then
		tee -a -- "$target" <"$default"
		rm "$default"
	fi
}

merge_history ~/.duckdb_history "$DUCKDB_HISTORY"
merge_history ~/.node_repl_history "$NODE_REPL_HISTORY"
merge_history ~/.sqlite_history "$SQLITE_HISTORY"
