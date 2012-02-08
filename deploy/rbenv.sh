#!/bin/sh
# Clone Repository

DESTINATION=~/.rbenv
REPOSITORY="git://github.com/sstephenson/rbenv.git"

rm -rf DESTINATION
git clone $RBENV_REPOSITORY $DESTINATION
