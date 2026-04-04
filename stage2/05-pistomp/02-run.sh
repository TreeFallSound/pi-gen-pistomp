#!/bin/bash -e

echo "Installing MOD software"
on_chroot << EOF

mkdir -p /home/${FIRST_USER_NAME}/tmp
cd /home/${FIRST_USER_NAME}/tmp

export NOOPT=true
[ ! -d Hylia ] && git clone --recursive https://github.com/falkTX/Hylia.git
cd Hylia
make
make install
cd ..

[ ! -d jack2 ] && git clone --branch v1.9.22 https://github.com/jackaudio/jack2.git
cd jack2
./waf configure
./waf build
./waf install
cd ..

# jack-example-tools provides jack_load/jack_unload v4
# Alternative source:
#[ ! -d jack-example-tools ] && git clone --branch 4 https://github.com/jackaudio/jack-example-tools.git
[ ! -d jack-example-tools ] && git clone --branch debian/4-4 https://salsa.debian.org/multimedia-team/jack-example-tools.git
cd jack-example-tools
meson setup --prefix=/usr/local build
ninja -C build
meson install -C build
cd ..

# debian 13 will include python3-lilv liblilv-dev
[ ! -d lilv-0.24.12 ] && \
  wget http://download.drobilla.net/lilv-0.24.12.tar.bz2 && \
  tar xvf lilv-0.24.12.tar.bz2
cd lilv-0.24.12
./waf configure --prefix=/usr/local --no-utils --no-bash-completion --pythondir=/usr/local/lib/python3.11/dist-packages
./waf build
./waf install
cd ..

[ ! -d browsepy ] && git clone https://github.com/micahvdm/browsepy.git
cd browsepy
pip3 install ./
cd ..

[ ! -d mod-host ] && git clone https://github.com/mod-audio/mod-host
cd mod-host
# This project has no tags - using the repo head from 2025-12-27
git checkout af11901d9d3ab02631b463853bd16d7881c4e7ca
make
make install
cd ..

[ ! -d mod-ui ] && git clone https://github.com/TreeFallSound/mod-ui.git
cd mod-ui
chmod +x setup.py
cd utils
make
cd ..
./setup.py install
cp -r default.pedalboard /home/${FIRST_USER_NAME}/data/.pedalboards
sed -i -e 's/collections.MutableMapping/collections.abc.MutableMapping/' /usr/local/lib/python3.11/dist-packages/tornado/httputil.py
cd ..

[ ! -d amidithru ] && git clone https://github.com/BlokasLabs/amidithru.git
cd amidithru
sed -i 's/CXX=g++.*/CXX=g++/' Makefile
make install
cd ..

[ ! -d touchosc2midi ] && git clone https://github.com/BlokasLabs/touchosc2midi.git
cd touchosc2midi
pip3 install ./
cd ..

[ ! -d mod-midi-merger ] && git clone https://github.com/mod-audio/mod-midi-merger
cd mod-midi-merger
# This project's cmake forces the install prefix to /usr for some reason, so disable that
# so that CMAKE_INSTALL_PREFIX can be used.
sed -i 's/^[[:space:]]*set(CMAKE_INSTALL_PREFIX[[:space:]]*\/usr)/# &/' CMakeLists.txt
[ -d build ] && rm -rf build
mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX=/usr/local ..
make
make install
cd ../..

[ ! -d mod-ttymidi ] && git clone https://github.com/moddevices/mod-ttymidi.git
cd mod-ttymidi
make install
cd ..
EOF
