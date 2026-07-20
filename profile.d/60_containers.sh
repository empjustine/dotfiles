#!/bin/sh

if [ -d "${HOME}/.kube/config.d" ]; then
	KUBECONFIG="$(find "${HOME}/.kube/config.d" -type f | tr '\n' ':')"
	export KUBECONFIG
fi
