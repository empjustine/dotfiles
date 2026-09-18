#!/bin/sh

set -x

# One run per report: truncated each run so report.txt stays readable.
date +%F >report.txt

status=0

# Both tools only parse sh/bash/dash — *.zsh is excluded here and
# syntax-checked with `zsh -n` below instead (SC1071 would fail every run).
find "${DOTFILES:-$HOME/dotfiles}" \( -name '*.sh' -o -name '*.bash' \) -type f -exec mise exec shfmt -- shfmt --write --indent 0 --binary-next-line --case-indent -- '{}' '+' >>report.txt 2>&1 || status=1
find "${DOTFILES:-$HOME/dotfiles}" \( -name '*.sh' -o -name '*.bash' \) -type f -exec mise exec shellcheck -- shellcheck --check-sourced --external-sources --severity=style --enable=all --exclude=SC2292,SC2250 '{}' '+' >>report.txt 2>&1 || status=1

if command -v zsh >/dev/null 2>&1; then
	for zsh_snippet in "${DOTFILES:-$HOME/dotfiles}"/profile.d/*.zsh; do
		zsh -n "$zsh_snippet" >>report.txt 2>&1 || status=1
	done
	unset zsh_snippet
fi

date +%F >>report.txt

# SC2292 (style): Prefer [[ ]] over [ ] for tests in Bash/Ksh/Busybox.
# SC2250 (style): Prefer putting braces around variable references even when not strictly required.
# Both are incompatible with the POSIX-clean *.sh requirement, hence excluded.

exit "$status"
