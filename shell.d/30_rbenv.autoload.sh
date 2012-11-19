#!/bin/sh

if [ -e $HOME/.rbenv/bin/rbenv ]; then
  export PATH="$HOME/.rbenv/bin:$PATH"
  eval "$(rbenv init -)"
else
  echo "rbenv not deployed"
fi
