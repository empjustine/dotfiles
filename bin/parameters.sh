#!/bin/sh

echo "Positional parameter test"
echo "\$0 (shell name): $0"
echo "\$1 (prog name) : $1"
echo "\$2 (1st param) : $2"
echo "\$3 (2nd param) : $3"
echo "\$# (# params)  : $#"
echo "\$@ (param list): $@"
echo "\$* (param list): $*"
echo "\$- (opts)      : $-"
echo "\$? (errorcode) : $?"
echo "\$$ (parent pid): $$"
echo "\$! (last bg id): $!"

