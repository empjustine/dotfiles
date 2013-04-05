#!/bin/sh

sudo apt-get install build-essential
git clone git://github.com/antirez/redis.git ~/repos/redis
cd ~/repos/redis
make