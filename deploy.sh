#!/bin/sh

set -x

cp "${DOTFILES:-$HOME/dotfiles}/bash_profile.bash" ~/.bash_profile
cp "${DOTFILES:-$HOME/dotfiles}/bashrc.bash" ~/.bashrc
cp "${DOTFILES:-$HOME/dotfiles}/zprofile.zsh" "${ZDOTDIR:-$HOME}/.zprofile"
cp "${DOTFILES:-$HOME/dotfiles}/zshrc.zsh" "${ZDOTDIR:-$HOME}/.zshrc"
