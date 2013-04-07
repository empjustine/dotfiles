#!/bin/sh

export REPOSITORY_ROOT=$HOME/repositories
export DOTFILES_ROOT=$REPOSITORY_ROOT/self/dotfiles

# Make vim the default editor
export EDITOR="vim"
export VISUAL="vim"

export BROWSER="firefox"

# Don’t clear the screen after quitting a manual page
export PAGER="less"
export MANPAGER="less -X"

export PATH=$DOTFILES_ROOT/bin:$PATH

# Silence beeps
setterm -blength 0
