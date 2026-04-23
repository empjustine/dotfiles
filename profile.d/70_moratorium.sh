#!/bin/sh

# @see https://github.com/mprpic/cooldowns

if [ -x "/home/linuxbrew/.linuxbrew/bin/mise" ]; then
	mise settings set install_before "7d"
	# min-release-age days
	mise exec node@24 -- npm config --global set min-release-age=7 ignore-scripts=true
	# min-release-age minutes
	mise exec pnpm@10 -- pnpm config set --location=global minimum-release-age 10080
fi

UV_EXCLUDE_NEWER="7 days"
PIP_UPLOADED_PRIOR_TO="$(date -u -d '7 days ago' '+%Y-%m-%dT%H:%M:%SZ')"
export UV_EXCLUDE_NEWER PIP_UPLOADED_PRIOR_TO

#if ! grep 'exclude-newer = "7 days"' "${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv.toml" >/dev/null 2>/dev/null; then
#	mkdir -p -- "${XDG_CONFIG_HOME:-$HOME/.config}/uv"
#	printf '\nexclude-newer = "7 days"\n' >>"${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv.toml"
#fi

# Deno (in project deno.json):
# { "minimumDependencyAge": "P7D" }
# deno install --minimum-dependency-age=P3D
# deno update --minimum-dependency-age=P3D
# deno outdated --minimum-dependency-age=P3D
