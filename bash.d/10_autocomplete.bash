#!/bin/bash

[ -f "/usr/share/git/completion/git-completion.bash" ] && \
    source /usr/share/git/completion/git-completion.bash || \
    echo "Arch Linux git-completion not avaliable"

source $DOTFILES_ROOT/bash-completion/bundler
source $DOTFILES_ROOT/bash-completion/rake

[ -f "$REPOSITORY_ROOT/bin/kerl/bash_completion/kerl" ] && \
    source $REPOSITORY_ROOT/bin/kerl/bash_completion/kerl || \
    echo "kerl bash autocompletion not avaliable"

source $HOME/.cabal/share/compleat-1.0/compleat_setup

