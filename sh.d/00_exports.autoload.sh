#!/bin/sh

# Make vim the default editor
export EDITOR="vim"
export VISUAL="vim"
export BROWSER="firefox"

# Don’t clear the screen after quitting a manual page
export PAGER="less"
export MANPAGER="less -X"

export EC2_PRIVATE_KEY=~/.ssh/pk-TMLADOPM64S5RL2J33RRDOS732VNYTJM.pem
export EC2_CERT=~/.ssh/cert-TMLADOPM64S5RL2J33RRDOS732VNYTJM.pem

export DOTFILES_PATH="$HOME/repositories/self/dotfiles"

export PATH="$DOTFILES_PATH/bin:$PATH"
