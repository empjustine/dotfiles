#!/bin/sh

sudo apt-get build-dep python-imaging
sudo apt-get install tcl-dev tcl8.4-dev tk-dev tk8.4-dev

sudo ln -s /usr/lib/i386-linux-gnu/libfreetype.so /usr/lib/
sudo ln -s /usr/lib/i386-linux-gnu/libjpeg.so /usr/lib/
sudo ln -s /usr/lib/i386-linux-gnu/libz.so /usr/lib/

cd /usr/include
sudo ln -s tcl8.4/ tcl
sudo ln -s tk8.4/ tk

sudo easy_install pip
sudo pip install tkinter-pypy
sudo pip install pil
