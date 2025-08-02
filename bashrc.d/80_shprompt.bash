#!/bin/bash

if [ -n "$PS1" ]; then
	# remove "@\h" "@$(hostname)"
	PS1="${PS1//@\\h/}"

	# remove '${PROMPT_USERHOST@P}'
	# remove '\[\e[${PROMPT_COLOR}${PROMPT_HIGHLIGHT:+;$PROMPT_HIGHLIGHT}m\]${PROMPT_USERHOST@P}'
	#PS1="${PS1/\\[\\e\[\${PROMPT_COLOR\}\${PROMPT_HIGHLIGHT:+;\$PROMPT_HIGHLIGHT\}m\\]\${PROMPT_USERHOST@P\}/}"
	PS1="${PS1//\${PROMPT_USERHOST@P\}/}"

	# remove ':' '${PROMPT_SEPARATOR@P}'
	PS1="${PS1//\${PROMPT_SEPARATOR@P\}/}"
fi
