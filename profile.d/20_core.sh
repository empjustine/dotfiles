#!/bin/sh

if [ -n "$BASH_VERSION" ]; then
	if [ -r /etc/bashrc ]; then
		. /etc/bashrc
	fi
	if [ -r "${PREFIX}/etc/bash.bashrc" ]; then
		. "${PREFIX}/etc/bash.bashrc"
	fi
fi

# https://docs.cloud.google.com/shell/docs/quotas-limits#bashrc_content
if [ -f "/google/devshell/bashrc.google" ]; then
	. "/google/devshell/bashrc.google"
fi

# https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cloudshellintro.htm#Cloud_Shell_Limitations
if [ -f "/etc/bashrc.cloudshell" ]; then
	. "/etc/bashrc.cloudshell"
fi
