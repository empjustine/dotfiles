#!/bin/bash

[ -f "/usr/share/git/completion/git-completion.bash" ] && \
    source /usr/share/git/completion/git-completion.bash || \
    echo "Arch Linux git-completion not avaliable"

[ -f "$REPOSITORY_ROOT/bin/kerl/bash_completion/kerl" ] && \
    source $REPOSITORY_ROOT/bin/kerl/bash_completion/kerl || \
    echo "kerl bash autocompletion not avaliable"

source $HOME/local/share/compleat-1.0/compleat_setup

