#!/bin/sh

sudo apt-get install ssh
mkdir -p ~/.ssh
cd ~/.ssh

# ./ssh_key.sh

#cat key.pub >> authorized_keys2
chmod 644 authorized_keys2