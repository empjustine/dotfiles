echo 'en_US.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen
echo 'LANG="en_US.UTF-8"' | sudo tee -a /etc/locale.conf
echo 'export LANGUAGE="en_AU:en_GB:en"' | sudo tee -a /etc/locale.conf
echo 'export LC_COLLATE="C"' | sudo tee -a /etc/locale.conf
sudo locale-gen
