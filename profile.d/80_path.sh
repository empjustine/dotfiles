#!/bin/sh

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"

for dir in \
	"${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims" \
	"/home/linuxbrew/.linuxbrew/sbin" \
	"/home/linuxbrew/.linuxbrew/bin" \
	"${XDG_DATA_HOME:-$HOME/.local/share}/JetBrains/Toolbox/scripts" \
	"/run/media/yoomuin/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/var/home/deck/bin" \
	"${HOME}/.local/bin" \
	"/usr/lib/wsl/lib"; do
	[ -d "${dir}" ] && PATH="${PATH}:${dir}"
done
unset dir

default_oci="${HOME}/.oci/config.d/ocid1.user.oc1..aaaaaaaaf3sb2fio74htiy5qs367vrcwl5fpxkwlw46r6xuurffdxfhoygba.config"
if [ -r "${default_oci}" ]; then
	OCI_CONFIG_FILE="${default_oci}"
	OCI_CLI_CONFIG_FILE="${default_oci}"
	export OCI_CONFIG_FILE OCI_CLI_CONFIG_FILE
fi
unset default_oci

if [ -x ~/.local/share/mise/shims/kubectl ] && [ -d "${HOME}/.kube/config.d" ]; then
	KUBECONFIG="$(find "${HOME}/.kube/config.d" -type f | tr '\n' ':')"
	export KUBECONFIG
fi
