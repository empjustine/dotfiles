#!/bin/sh

if [ -d "${HOME}/.local/bin" ]; then
	PATH="${HOME}/.local/bin:${PATH}"
fi
if [ -d /run/media/yoomuin/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/var/home/deck/bin/ ]; then
	PATH="/run/media/yoomuin/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/var/home/deck/bin/:${PATH}"
fi
