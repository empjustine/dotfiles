#!/bin/sh

cd
wget https://downloads.sf.net/project/zero-install/0install/1.13/0install-1.13.tar.bz2
tar xjf 0install-1.13.tar.bz2
cd 0install-1.13

alias python=python2
python setup.py install --home ~ --install-data ~/.local