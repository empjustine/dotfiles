#!/bin/sh

if [ -e $HOME/.rbenv/bin/rbenv ]; then
  export PATH="$HOME/.rbenv/bin:$PATH"
  eval "$(rbenv init -)"
else
  echo "rbenv not deployed, using user gems"
  export PATH="$HOME/.gem/ruby/1.9.1/bin:$PATH"
fi
