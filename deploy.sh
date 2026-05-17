#!/bin/sh

set -x

cp "${DOTFILES:-$HOME/dotfiles}/bash_profile.bash" ~/.bash_profile
cp "${DOTFILES:-$HOME/dotfiles}/bashrc.bash" ~/.bashrc
cp "${DOTFILES:-$HOME/dotfiles}/zprofile.zsh" "${ZDOTDIR:-$HOME}/.zprofile"
cp "${DOTFILES:-$HOME/dotfiles}/zshrc.zsh" "${ZDOTDIR:-$HOME}/.zshrc"

if [ -x "/home/linuxbrew/.linuxbrew/bin/mise" ]; then
	mise settings set java.shorthand_vendor "temurin"
	mise settings set install_before "7d"
	# min-release-age days
	mise exec node@24 -- npm config --global set min-release-age=7 ignore-scripts=true
	# min-release-age minutes
	mise exec pnpm@10 -- pnpm config set --location=global minimum-release-age 10080
fi

if ! grep 'exclude-newer = "7 days"' "${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv.toml" >/dev/null 2>/dev/null; then
	mkdir -p -- "${XDG_CONFIG_HOME:-$HOME/.config}/uv"
	printf '\nexclude-newer = "7 days"\n' >>"${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv.toml"
fi