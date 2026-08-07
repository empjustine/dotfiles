#!/bin/bash

if [ -n "$BASH_VERSION" ]; then
	if [ -r /etc/bashrc ]; then
		# shellcheck source=/dev/null
		. /etc/bashrc
	fi
	# msys2 / Git Bash (and Debian/Ubuntu) keep their system bashrc at
	# /etc/bash.bashrc; Fedora's /etc/bashrc is handled above.
	if [ -r /etc/bash.bashrc ]; then
		# shellcheck source=/dev/null
		. /etc/bash.bashrc
	fi
	# termux $PREFIX = /data/data/com.termux/files/usr
	if [ -r /data/data/com.termux/files/usr/etc/profile ]; then
		# shellcheck source=/dev/null
		. /data/data/com.termux/files/usr/etc/profile
	fi
	# https://docs.cloud.google.com/shell/docs/quotas-limits#bashrc_content
	if [ -r /google/devshell/bashrc.google ]; then
		# shellcheck source=/dev/null
		. /google/devshell/bashrc.google
	fi
	# https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cloudshellintro.htm#Cloud_Shell_Limitations
	if [ -r /etc/bashrc.cloudshell ]; then
		# shellcheck source=/dev/null
		. /etc/bashrc.cloudshell
	fi
else
	printf '%s\n' "dotfiles: bash-only snippet sourced under a non-bash shell; skipping" >&2
fi
