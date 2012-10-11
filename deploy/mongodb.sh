#!/bin/sh

sudo apt-get install git-core scons build-essential
sudo apt-get install libboost-dev libboost-program-options-dev libboost-thread-dev libboost-filesystem-dev

git clone git://github.com/mongodb/mongo.git ~/repos/mongo
cd ~/repos/mongo/
scons all
scons --prefix=~/repos/.mongo install