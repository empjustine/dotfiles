#!/bin/sh

# Make vim the default editor
export EDITOR="vim"
export VISUAL="vim"
export BROWSER="firefox"

# Don’t clear the screen after quitting a manual page
export PAGER="less"
export MANPAGER="less -X"

export DOTFILES_PATH=$HOME/repositories/self/dotfiles

export PATH=$DOTFILES_PATH/bin:$PATH

# Silence beeps
setterm -blength 0
