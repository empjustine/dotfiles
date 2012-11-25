#!/bin/sh

cd ~/repositories/bin/compleat
sudo pacman -S haskell-parsec

./Setup.lhs configure --user
./Setup.lhs build
./Setup.lhs install
