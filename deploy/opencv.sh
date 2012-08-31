#!/bin/sh

sudo apt-get install build-essential checkinstall cmake pkg-config yasm
sudo apt-get install libtiff4-dev libjpeg-dev libjasper-dev libpng-dev
sudo apt-get install python-dev
sudo apt-get install libtbb2 libtbb-dev
sudo apt-get install libqt4-dev libgtk2.0-dev
sudo apt-get install python-dev cmake libtbb2 libtbb-dev pkg-config
sudo pip install numpy sphinx

mkdir opencv_build/
cd opencv_build/

echo "/usr/local/lib" | sudo tee -A /etc/ld.so.conf
sudo ldconf

sudo cmake -D CMAKE_BUILD_TYPE=RELEASE -D CMAKE_INSTALL_PREFIX=/usr/local -D BUILD_PYTHON_SUPPORT=ON -D WITH_OPENGL=ON -D WITH_TBB=ON opencv/

make
sudo make install
