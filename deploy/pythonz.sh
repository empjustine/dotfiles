#!/bin/sh

sudo apt-get install python-setuptools
sudo easy_install pip
sudo pip install virtualenvwrapper
curl -kL https://raw.github.com/saghul/pythonz/master/pythonz-install | bash

#pythonz install 2.7.3
#mkvirtualenv -p ~/.pythonz/pythons/CPython-2.7.3/bin/python cpython273 && deactivate