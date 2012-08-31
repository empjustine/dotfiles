#!/bin/sh

if [ -e /usr/local/bin/virtualenvwrapper.sh ] && \
 [ -e $HOME/.pythonz/etc/bashrc ]; then
  source /usr/local/bin/virtualenvwrapper.sh
  source $HOME/.pythonz/etc/bashrc
else
  echo "pythonz not deployed"
fi
