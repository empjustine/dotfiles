#!/bin/sh
# unproxy.sh — run a command with the conventional proxy variables removed.
# Gate: any shell; never sourced (it execs the command).

exec env \
	-u all_proxy \
	-u ALL_PROXY \
	-u http_proxy \
	-u HTTP_PROXY \
	-u https_proxy \
	-u HTTPS_PROXY \
	"$@"
