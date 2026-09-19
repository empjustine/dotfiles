# dotfiles

Known login flows:

/etc/zshenv → ~/.zshenv → ~/.zprofile → ~/.zshrc → ~/.zlogin → ~/.zlogout

~/.bash_profile → login

~/.bashrc → non login

## install

```sh
for target in ~/.bash_profile ~/.bashrc "${ZDOTDIR:-$HOME}/.zprofile" "${ZDOTDIR:-$HOME}/.zshrc"; do
	cp "${DOTFILES:-$HOME/dotfiles}/src-dotfiles.sh" "$target"
done
```

# lint

```sh
find "${DOTFILES:-$HOME/dotfiles}" -name '*sh' -type f -exec shfmt --write --indent 0 --binary-next-line --case-indent -- '{}' '+'
find "${DOTFILES:-$HOME/dotfiles}" -name '*sh' -type f -exec shellcheck --check-sourced --external-sources --severity=style --enable=all --exclude=SC2250,SC2292 '{}' '+'
```

## credits

*None currently bundled — the last third-party component (rcaloras'
bash-preexec, MIT) was removed with the atuin ≥ 18.18 floor (DR-037);
see DR-010/DR-025 for its history.*
