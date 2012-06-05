#!/bin/sh

sudo apt-get install zlib1g-dev libreadline-dev openssl libssl-dev curl
sudo yum install gcc readline-devel bison zlib-devel openssl-devel

rbenv-install 1.9.2-p290
rbenv global 1.9.2-p290

