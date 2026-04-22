#!/bin/sh

set -x

date --iso-8601 | tee -a report.txt
mise exec shfmt -- find "${DOTFILES:-$HOME/dotfiles}" -name '*sh' -type f -exec shfmt --write --indent 0 --binary-next-line --case-indent -- '{}' '+' | tee -a report.txt
mise exec shellcheck -- find "${DOTFILES:-$HOME/dotfiles}" -name '*sh' -type f -exec shellcheck --check-sourced --external-sources --severity=style --enable=all --exclude=SC2292,SC2250 '{}' '+' | tee -a report.txt
date --iso-8601 | tee -a report.txt

# SC2292 (style): Prefer [[ ]] over [ ] for tests in Bash/Ksh/Busybox.
# SC2250 (style): Prefer putting braces around variable references even when not strictly required.
