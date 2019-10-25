# Login shell:
#         /etc/profile
#         ~/.bash_profile
#         ~/.bash_login
#         ~/.profile
test -f "${XDG_CONFIG_HOME:-$HOME/.config}/profile" && . "${XDG_CONFIG_HOME:-$HOME/.config}/profile"