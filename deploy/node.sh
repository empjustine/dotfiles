#!/bin/sh

git clone https://github.com/joyent/node.git ~/repos/node
cd ~/build/node

mkdir -p ~/bin/.node
export PREFIX=~/bin/.node; ./configure
make
make install