#!/bin/sh

sudo apt-get install python-dev cmake libtbb2 libtbb-dev pkg-config
sudo pip install numpy sphinx

mkdir opencv_build/
cd opencv_build/

sudo cmake -D:CMAKE_BUILD_TYPE=RELEASE -D:CMAKE_INSTALL_PREFIX=/usr/local -D:BUILD_PYTHON_SUPPORT=ON opencv/

make
sudo make install
sudo apt-get install libopencv-core-dev
