#!/bin/bash

# Solarized Prompt
# inspired by:
# Sexy Bash Prompt, inspired by "Extravagant Zsh Prompt"
# A big thanks to \amethyst on Freenode

eval `dircolors -b ~/.dotfiles/submodules/solarized/dircolors-solarized/dircolors.ansi-dark`

# solarized color theme
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BOLD=$(tput bold)
RESET=$(tput sgr0)

# The following properties add visual indicators about the state of the git repo
# in the current directory to the end of the PS1 prompt; even though these icons
# can be very informative, they significantly slow down the "calculation" of PS1
# resulting in noticeable delays when working in an interactive shell; to avoid
# these delays any or all of these properties can be unset in your ~/.after_sbrc

# Show * if there are unstaged changes
#  and + if staged and uncommitted changes.
GIT_PS1_SHOWDIRTYSTATE=1
# Show $ if there are stashed changes.
GIT_PS1_SHOWSTASHSTATE=1
# Show % if there are untracked files.
GIT_PS1_SHOWUNTRACKEDFILES=1
# Show < if there are unpulled changes,
#      > if there are unpushed changes,
#     <> if there are both,
#   or = if everything’s synced.
GIT_PS1_SHOWUPSTREAM=1
export PS1="\$(history -a)\[$RESET\]\[$CYAN\]\u@\h \[$MAGENTA\]\w\[$RED\]\$(__git_ps1 2> /dev/null)\n\[$WHITE\]\$ \[$RESET\]"