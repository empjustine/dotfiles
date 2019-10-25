# Interactive shell:
#         /etc/bash.bashrc
#         ~/.bashrc
test -f "${XDG_CONFIG_HOME:-$HOME/.config}/bashrc" && . "${XDG_CONFIG_HOME:-$HOME/.config}/bashrc"