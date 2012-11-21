#!/bin/sh

cd $REPOSITORY_ROOT/bin/phantomjs
git checkout 1.7
./build.sh

sudo pacman -S upx

deploy/package.sh
