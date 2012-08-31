#!/bin/sh

if [ -e $HOME/bin/.erl-r15b/activate ]; then
  source $HOME/bin/.erl-r15b/activate
else
  echo "no erl-r15b detected"
fi
