#!/bin/sh

git clone https://github.com/joyent/node.git ~/.nodejs
cd ~/.nodejs
mkdir ~/opt
export PREFIX=~/opt; ./configure
make
make install