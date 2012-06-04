#!/bin/sh

wget http://download.lighttpd.net/lighttpd/releases-1.4.x/lighttpd-1.4.31.tar.xz
tar -xzvf lighttpd-1.4.31.tar.xz

cd lighttpd-1.4.31
./configure --with-openssl
make install exec_prefix=~

sudo mkdir -p /var/www/html
sudo groupadd lighttpd
sudo useradd -g lighttpd -d /var/www -s /bin/false lighttpd
sudo chown -R lighttpd.lighttpd /var/www
sudo chown -R lighttpd.lighttpd /var/log/lighttpd