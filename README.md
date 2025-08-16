# dotfiles

## install

```sh
# grep '' ~/.bash* "${ZDOTDIR:-$HOME}/.z"*

printf '. %q\n' "${DOTFILES:-$HOME/dotfiles}/profile.sh" >~/.bash_profile
printf '. %q\n' "${DOTFILES:-$HOME/dotfiles}/profile.sh" >~/.bashrc
printf '. %q\n' "${DOTFILES:-$HOME/dotfiles}/profile.sh" >"${ZDOTDIR:-$HOME}/.zprofile"
printf '. %q\n' "${DOTFILES:-$HOME/dotfiles}/profile.sh" >"${ZDOTDIR:-$HOME}/.zshrc"
printf '. %q\n' "${DOTFILES:-$HOME/dotfiles}/profile.sh" >"${ZDOTDIR:-$HOME}/.mksh"
```

# lint

```sh
find "${DOTFILES:-$HOME/dotfiles}" -name '*sh' -type f -exec shfmt --write --indent 0 --binary-next-line --case-indent -- '{}' '+'
find "${DOTFILES:-$HOME/dotfiles}" -name '*sh' -type f -exec shellcheck --check-sourced --external-sources --severity=style --enable=all --exclude=SC2250,SC2292 '{}' '+'
```
