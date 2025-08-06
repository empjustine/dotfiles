#!/bin/bash

if [ -n "$PS1" ]; then
	PS1="${PS1//@\\h/}"
	PS1="${PS1//\${PROMPT_USERHOST@P\}/}"
	PS1="${PS1//\${PROMPT_SEPARATOR@P\}/}"
fi
