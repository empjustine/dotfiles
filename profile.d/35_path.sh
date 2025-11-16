#!/bin/sh

PATH="/usr/local/bin:/usr/bin"

PATH="${PATH}:${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"
PATH="${PATH}:/home/linuxbrew/.linuxbrew/bin"

PATH="${PATH}:${XDG_DATA_HOME:-$HOME/.local/share}/JetBrains/Toolbox/scripts"
PATH="${PATH}:/run/media/yoomuin/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/var/home/deck/bin"
PATH="${PATH}:${HOME}/.local/bin"
PATH="${PATH}:/usr/lib/wsl/lib"
