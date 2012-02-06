#!/bin/sh

./kerl.sh

kerl list releases

kerl build R15B r15b
kerl list builds

kerl install r15b ~/erl/
