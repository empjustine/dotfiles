#!/bin/bash

if [ -n "$BASH_VERSION" ]; then
	[ -r /etc/bashrc ] && . /etc/bashrc
	[ -r "${PREFIX}/etc/bash.bashrc" ] && . "${PREFIX}/etc/bash.bashrc"

	# https://docs.cloud.google.com/shell/docs/quotas-limits#bashrc_content
	[ -f "/google/devshell/bashrc.google" ] && . "/google/devshell/bashrc.google"
	# https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cloudshellintro.htm#Cloud_Shell_Limitations
	[ -f "/etc/bashrc.cloudshell" ] && . "/etc/bashrc.cloudshell"
fi
