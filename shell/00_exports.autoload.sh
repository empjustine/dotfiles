#!/bin/sh

# Make vim the default editor
export EDITOR="vim"

# Don’t clear the screen after quitting a manual page
export MANPAGER="less -X"
export TERM=xterm-256color

export EC2_PRIVATE_KEY=~/.ssh/pk-TMLADOPM64S5RL2J33RRDOS732VNYTJM.pem
export EC2_CERT=~/.ssh/cert-TMLADOPM64S5RL2J33RRDOS732VNYTJM.pem

export DOTFILES_PATH="$HOME/.dotfiles"
export REPOSITORY_PATH="$HOME/repos"

export PATH="$DOTFILES_PATH/bin:$PATH"
