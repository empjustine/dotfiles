#!/bin/bash

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac
# if [ -n "${-//[^i]}" ]; then
#     ...
# fi

test -f "${XDG_DATA_HOME:-$HOME/.local/share}/_asdf/asdf.sh" && . "${XDG_DATA_HOME:-$HOME/.local/share}/_asdf/asdf.sh"