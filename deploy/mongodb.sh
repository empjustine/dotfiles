#!/bin/sh

sudo apt-get install tcsh git-core scons g++
sudo apt-get install libpcre++-dev libboost-dev libreadline-dev xulrunner-1.9.2-dev
sudo apt-get install libboost-program-options-dev libboost-thread-dev libboost-filesystem-dev libboost-date-time-dev

git clone git://github.com/mongodb/mongo.git ~/.mongo
cd ~/.mongo
scons all
scons --prefix=~/opt/mongo install