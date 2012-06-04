#!/bin/sh
echo "symlinks flying..."

ln -s '~/.dotfiles/home/vimrc'           '~/.vimrc'
ln -s '~/.dotfiles/home/selected_editor' '~/.selected_editor'
ln -s '~/.dotfiles/home/gitconfig'       '~/.gitconfig'
ln -s '~/.dotfiles/home/gitignore'       '~/.gitignore'
ln -s '~/.dotfiles/home/gitk'            '~/.gitk'
ln -s '~/.dotfiles/home/inputrc'         '~/.inputrc'
ln -s '~/.dotfiles/home/irbrc'           '~/.irbrc'

ln -s '~/.dotfiles/submodules/vim/'      '~/.vim'

ln -s '~/.dotfiles/config/geany/'        '~/.config/geany'
