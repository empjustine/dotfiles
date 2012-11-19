#!/bin/sh
cd

mkdir -p repositories/self/
cd       repositories/self/
git clone git@github.com:empjustine/dotfiles.git

##### ##### ##### #####
cd

mkdir -p repositories/bin/
cd       repositories/bin/
git clone git@github.com:spawngrid/kerl.git
git clone git@github.com:basho/rebar.git
git clone git@github.com:sstephenson/ruby-build.git
git clone git@github.com:isaacs/nave.git

##### ##### ##### #####
cd

mkdir -p repositories/vim/
cd       repositories/vim/
git clone git@github.com:tpope/vim-pathogen.git
git clone git@github.com:Lokaltog/vim-powerline.git
git clone git@github.com:nvie/vim-togglemouse.git
git clone git@github.com:vim-ruby/vim-ruby.git
git clone git@github.com:altercation/vim-colors-solarized.git

##### ##### ##### #####
cd

mkdir -p repositories/solarized/
cd       repositories/solarized/
git clone git@github.com:seebi/dircolors-solarized.git
git clone git://github.com/ibotty/solarized-xmonad.git

