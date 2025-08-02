# dotfiles

install

```sh
grep '' ~/.bash_profile ~/.bashrc ~/.zprofile ~/.zshrc

printf '. %q\n' "${DOTFILES:-$HOME/dotfiles}/bash_profile.bash" >~/.bash_profile
printf '. %q\n' "${DOTFILES:-$HOME/dotfiles}/bashrc.bash" >~/.bashrc
printf '. %q\n' "${DOTFILES:-$HOME/dotfiles}/zprofile.zsh" >~/.zprofile
printf '. %q\n' "${DOTFILES:-$HOME/dotfiles}/zshrc.zsh" >~/.zshrc
```