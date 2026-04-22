#!/bin/sh

if [ -x "/home/linuxbrew/.linuxbrew/bin/mise" ]; then
	mise settings set install_before "7d"
	mise exec node@24 -- npm config --global set min-release-age=7 ignore-scripts=true
	mise exec pnpm@10 -- pnpm config set --location=global minimum-release-age 10080
fi

if ! grep 'exclude-newer = "7 days"' "${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv.toml" >/dev/null 2>/dev/null; then
	mkdir -p -- "${XDG_CONFIG_HOME:-$HOME/.config}/uv"
	printf '\nexclude-newer = "7 days"\n' >>"${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv.toml"
fi
