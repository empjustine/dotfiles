#!/bin/bash

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

alias 'cd..'='cd ..'
alias 'cd....'='cd ../..'

alias ..='cd ..'
alias ....='cd ../..'
alias ......='cd ../../..'
alias ........='cd ../../../..'

alias more='less'

alias rot13='tr a-zA-Z n-za-mN-ZA-M'

# IP addresses
alias myip="dig +short myip.opendns.com @resolver1.opendns.com"

# DWIM
alias vo,=vim
alias vom=vim
alias bim=vim
alias cim=vim
