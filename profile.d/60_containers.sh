#!/bin/sh

if [ -d "${HOME}/.kube/config.d" ]; then
	# Native Win32 consumers (kubectl.exe) expect ';' list separators.
	KUBECONFIG_SEP=":"
	case "$(uname -s)" in
		*MINGW*|*MSYS*|*CYGWIN*) KUBECONFIG_SEP=";" ;;
	esac
	KUBECONFIG="$(find "${HOME}/.kube/config.d" -type f | tr '\n' "$KUBECONFIG_SEP")"
	export KUBECONFIG
	unset KUBECONFIG_SEP
fi
