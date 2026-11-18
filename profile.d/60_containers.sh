#!/bin/sh

# KUBECONFIG from ~/.kube/config.d. Only set when the directory actually
# contains files: an empty config.d must not clobber an inherited KUBECONFIG
# (DR-032, DR-034).
if [ -d "${HOME}/.kube/config.d" ]; then
	kube_list="$(find "${HOME}/.kube/config.d" -type f | tr '\n' ':')"
	if [ -n "$kube_list" ]; then
		KUBECONFIG="$kube_list"
		export KUBECONFIG
	fi
	unset kube_list
fi
