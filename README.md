# dotfiles

## install

```sh
cp "${DOTFILES:-$HOME/dotfiles}/bash_profile.sh" >~/.bash_profile
cp "${DOTFILES:-$HOME/dotfiles}/bashrc.bash" >~/.bashrc
cp "${DOTFILES:-$HOME/dotfiles}/zprofile.zsh" "${ZDOTDIR:-$HOME}/.zprofile"
cp "${DOTFILES:-$HOME/dotfiles}/zshrc.zsh" "${ZDOTDIR:-$HOME}/.zshrc"
```

# lint

```sh
find "${DOTFILES:-$HOME/dotfiles}" -name '*sh' -type f -exec shfmt --write --indent 0 --binary-next-line --case-indent -- '{}' '+'
find "${DOTFILES:-$HOME/dotfiles}" -name '*sh' -type f -exec shellcheck --check-sourced --external-sources --severity=style --enable=all --exclude=SC2250,SC2292 '{}' '+'
```

## credits

this package bundles bash-preexec. Copyright (c) 2017 Ryan Caloras and contributors. Full source code avaliable at https://github.com/rcaloras/bash-preexec , The MIT License.
