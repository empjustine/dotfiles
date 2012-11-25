#!/bin/sh

####
#http://www.etalabs.net/sh_tricks.html

####
#Shell-quoting arbitrary strings
quote () { printf %s\\n "$1" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/" ; }

####
#Does a given string match a given filename (glob) pattern?
fnmatch () { case "$2" in $1) return 0 ;; esac ; return 1 ; }

