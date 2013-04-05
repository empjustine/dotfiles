#!/bin/sh

#ubuntu
if [ -e /usr/local/bin/virtualenvwrapper.sh ] && \
 [ -e $HOME/.pythonz/etc/bashrc ]; then
  source /usr/local/bin/virtualenvwrapper.sh
  source $HOME/.pythonz/etc/bashrc
else
  echo "pythonz not deployed"
fi

#archlinux
export WORKON_HOME=~/.virtualenvs
if [ -e /usr/bin/virtualenvwrapper.sh ]; then
  source /usr/bin/virtualenvwrapper.sh
else
  echo "virtualenvwrapper not deployed"
fi
