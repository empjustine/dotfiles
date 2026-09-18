#!/bin/sh

# if [ -x /usr/bin/podman ]; then
# 	# CPU/Vulkan image
# 	RAMALAMA_IMAGE='quay.io/ramalama/ramalama:latest'
# 	export RAMALAMA_IMAGE
# fi
#
# default_oci="${HOME}/.oci/config.d/ocid1.user.oc1..aaaaaaaaf3sb2fio74htiy5qs367vrcwl5fpxkwlw46r6xuurffdxfhoygba.config"
# if [ -r "${default_oci}" ]; then
# 	OCI_CONFIG_FILE="${default_oci}"
# 	OCI_CLI_CONFIG_FILE="${default_oci}"
# 	export OCI_CONFIG_FILE OCI_CLI_CONFIG_FILE
# fi
# unset default_oci
#
if [ -d "${HOME}/.kube/config.d" ]; then
	# Native Win32 consumers (kubectl.exe) expect ';' list separators.
	KUBECONFIG_SEP=":"
	case "$(uname -s)" in
		*MINGW* | *MSYS* | *CYGWIN*) KUBECONFIG_SEP=";" ;;
		*) : ;;
	esac
	kube_list="$(find "${HOME}/.kube/config.d" -type f | tr '\n' "$KUBECONFIG_SEP")"
	# Only set when the directory actually contains files: an empty config.d
	# must not clobber an inherited KUBECONFIG with an empty string.
	if [ -n "$kube_list" ]; then
		KUBECONFIG="$kube_list"
		export KUBECONFIG
	fi
	unset KUBECONFIG_SEP kube_list
fi
