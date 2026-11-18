#!/bin/sh
# 60_kubeconfig.sh — KUBECONFIG from ~/.kube/config.d (DR-032).
#
# Gate: none — env-only and cheap, so every shell and every interactivity.
# Side effect: exports KUBECONFIG; an inherited one is left alone when the
# directory is missing or empty — an empty config.d must not clobber it
# (DR-034).
if [ -d "${HOME}/.kube/config.d" ]; then
	kube_list="$(find "${HOME}/.kube/config.d" -type f | tr '\n' ':')"
	if [ -n "$kube_list" ]; then
		KUBECONFIG="$kube_list"
		export KUBECONFIG
	fi
	unset kube_list
fi
