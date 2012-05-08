#!/bin/bash

# limitless .bash_history
unset HISTFILESIZE

# maximum in-memory history lines
# 2**32 - 1
export HISTSIZE=32767

# Make some commands not show up in history
export HISTCONTROL=ignoreboth:erasedups
export HISTIGNORE="ls:ls *:cd:cd -:cd ~:pwd:exit:date:reset:clear:history:bg:fg:ps:date:* --help:man *"

shopt -s histappend
