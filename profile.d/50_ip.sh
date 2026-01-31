#!/bin/sh

if [ -d ~/storage/shared/Documents/markor ]; then
	ip --json addr >~/storage/shared/Documents/markor/ip.json
fi
