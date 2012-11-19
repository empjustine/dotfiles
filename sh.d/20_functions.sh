#!/bin/sh

####
#shell-quotes source string
quote () { printf %s\\n "$1" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/" ; }
