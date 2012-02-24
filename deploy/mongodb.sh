#!/bin/sh

sudo apt-get install git-core scons build-essential
sudo apt-get install libboost-dev libboost-program-options-dev libboost-thread-dev libboost-filesystem-dev

git clone git://github.com/mongodb/mongo.git ~/build/mongo
cd ~/build/mongo
scons all
scons --prefix=~/bin/.mongo install