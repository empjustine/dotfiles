#!/bin/sh

set -x

find "${DOTFILES:-$HOME/dotfiles}" -name '*sh' -type f -exec shfmt --write --indent 0 --binary-next-line --case-indent -- '{}' '+'
find "${DOTFILES:-$HOME/dotfiles}" -name '*sh' -type f -exec shellcheck --check-sourced --external-sources --severity=style --enable=all --exclude=SC2250,SC2292 '{}' '+'
