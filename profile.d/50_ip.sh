#!/bin/sh

# Interactive-only: this writes into shared Android storage on every shell
# that would otherwise run it, including `ssh host cmd` (DR-017 guard shape).
case "$-" in
	*i*) ;;
	*) return 0 ;;
esac

if [ -d ~/storage/shared/Documents/markor ]; then
	ip --json addr >~/storage/shared/Documents/markor/ip.json
fi
