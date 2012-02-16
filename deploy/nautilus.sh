#!/bin/sh

sudo apt-get install dconf-tools
#dconf write /org/gnome/desktop/background/show-desktop-icons false

cd

mv .config/Thunar/uca.xml .config/Thunar/uca.xml.bak
sed 's/<\/actions>$/<action><icon>nautilus<\/icon><name>Open in Nautilus<\/name><command>nautilus %F<\/command><description><\/description><patterns>*<\/patterns><startup-notify\/><directories\/><\/action><\/actions>/' .config/Thunar/uca.xml.bak > .config/Thunar/uca.xml

#gconftool-2 --set --type=bool /apps/nautilus/preferences/show_desktop false
#gconftool-2 --set --type=bool /desktop/gnome/background/draw_background false
gconftool-2 --set --type=string /desktop/gnome/url-handlers/file/command 'nautilus "%s"'
gconftool-2 --set --type=bool /desktop/gnome/url-handlers/file/enabled true
gconftool-2 --set --type=bool /desktop/gnome/url-handlers/file/need-terminal false

gsettings set org.gnome.desktop.default-applications.terminal exec /usr/bin/xfce4-terminal
sudo apt-get install libgnome2-0