#!/bin/bash -e

echo "Installing MOD software"
on_chroot << EOF

mkdir -p /home/${FIRST_USER_NAME}/tmp
cd /home/${FIRST_USER_NAME}/tmp

export NOOPT=true
git clone --recursive https://github.com/falkTX/Hylia.git
cd Hylia
make
make install
cd ..

git clone https://github.com/micahvdm/jack2.git
cd jack2
./waf configure
./waf build
./waf install
cd ..

git clone https://github.com/micahvdm/browsepy.git
cd browsepy
pip3 install ./
cd ..

git clone https://github.com/micahvdm/mod-host.git
cd mod-host
make
make install
cd ..

git clone https://github.com/TreeFallSound/mod-ui.git
cd mod-ui
chmod +x setup.py
cd utils
make
cd ..
./setup.py install
cp -r default.pedalboard /home/${FIRST_USER_NAME}/data/.pedalboards
sed -i -e 's/collections.MutableMapping/collections.abc.MutableMapping/' /usr/local/lib/python3.11/dist-packages/tornado/httputil.py
cd ..

git clone https://github.com/BlokasLabs/amidithru.git
cd amidithru
sed -i 's/CXX=g++.*/CXX=g++/' Makefile
make install
cd ..

git clone https://github.com/micahvdm/touchosc2midi.git
cd touchosc2midi
pip3 install ./
cd ..

git clone https://github.com/micahvdm/mod-midi-merger.git
cd mod-midi-merger
mkdir build && cd build
cmake ..
make
make install
cd ..

git clone https://github.com/moddevices/mod-ttymidi.git
cd mod-ttymidi
make install
cd ..

wget http://download.drobilla.net/lilv-0.24.12.tar.bz2
tar xvf lilv-0.24.12.tar.bz2
cd lilv-0.24.12

./waf configure --prefix=/usr/local  --static --static-progs --no-shared --no-utils --no-bash-completion --pythondir=/usr/local/lib/python3.11/dist-packages
./waf build
./waf install
cd ..

EOF

