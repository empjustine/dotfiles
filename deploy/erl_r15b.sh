#!/bin/sh

./kerl.sh

sudo apt-get install build-essential libncurses5-dev openssl libssl-dev

kerl list releases

kerl build R15B r15b
kerl list builds

kerl install r15b ~/.erl-r15b/
