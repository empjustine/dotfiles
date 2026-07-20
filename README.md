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

this package bundles bash-preexec. Copyright (c) 2017 Ryan Caloras and contributors. Full source code avaliable at https://github.com/rcaloras/bash-preexec , The MIT License.
