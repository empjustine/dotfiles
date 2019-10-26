#!/bin/bash

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac
# if [ -n "${-//[^i]}" ]; then
#         ...
# fi

HISTFILE="${XDG_DATA_HOME:-$HOME/.local/share}/bash_history"
export HISTFILE
mkdir -p "$(dirname "${HISTFILE}")"

# Append to $HISTFILE instead of overwriting it -- this stops terminals
# from overwriting one another's histories.
shopt -s histappend

# Only load the last 1000 lines from your $HISTFILE in ram
HISTSIZE=1000
export HISTSIZE

# Don't truncate $HISTFILE -- keep all your history, ever.
unset HISTFILESIZE

# Add a ISO 8601 timestamp to each history entry.
HISTTIMEFORMAT=': %FT%T ; '
export HISTTIMEFORMAT

# Don't remember trivial 1- and 2-letter commands.
HISTIGNORE=?:??
export HISTIGNORE

# What it says.
HISTCONTROL=ignoredups
export HISTCONTROL

# Save each history entry immediately (protects against terminal crashes/
# disconnections, and interleaves commands from multiple terminals in correct
# chronological order).
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
export PROMPT_COMMAND
