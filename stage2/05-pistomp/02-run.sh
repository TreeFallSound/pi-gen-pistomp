#!/bin/bash -e

# Copy the patch into the chroot before the main build block
install -m 644 files/patches/pi-controller-reset.patch "${ROOTFS_DIR}/tmp/"

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
# Critical stability fix: clear PI controller integrator windup on ringbuffer
# reset. Without this, failure rate ramps monotonically from jackd start.
# See stage2/05-pistomp/files/patches/pi-controller-reset.patch for the diagnosis.
git apply /tmp/pi-controller-reset.patch
# Drop the bundled waflib so we use system waf, which supports Python 3.12+
# (the bundled waf uses the `imp` module removed in 3.12).
rm -rf waflib
waf configure
waf build
waf install
cd ..

# jack-example-tools provides jack_load/jack_unload v4
[ ! -d jack-example-tools ] && git clone --branch debian/4-4 https://salsa.debian.org/multimedia-team/jack-example-tools.git
cd jack-example-tools
meson setup --prefix=/usr/local build
ninja -C build
meson install -C build
cd ..

# python3-lilv and liblilv-dev are available via apt on trixie (>=0.24.26).
# No source build needed — installed via 00-packages.

[ ! -d browsepy ] && git clone https://github.com/micahvdm/browsepy.git
cd browsepy
pip3 install ./
cd ..

[ ! -d mod-host ] && git clone --branch fix/effect-drain-midi https://github.com/sastraxi/mod-host.git mod-host
cd mod-host
make
make install
cd ..

# mod-ui requires tornado==4.3 which is incompatible with Python 3.13.
# Run it in an isolated Python 3.11 venv, the same pattern as pistomp-arch.
[ ! -d mod-ui ] && git clone https://github.com/TreeFallSound/mod-ui.git
cd mod-ui
chmod +x setup.py
cd utils
make
cd ..
python3.11 -m venv /opt/mod-ui-venv
/opt/mod-ui-venv/bin/pip install tornado==4.3
# tornado 4.x uses collections.MutableMapping, removed in Python 3.10+.
sed -i -e 's/collections\.MutableMapping/collections.abc.MutableMapping/g' \
    /opt/mod-ui-venv/lib/python3.11/site-packages/tornado/httputil.py
/opt/mod-ui-venv/bin/python setup.py install
cp -r default.pedalboard /home/${FIRST_USER_NAME}/data/.pedalboards
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
# cmake forces install prefix to /usr, override it so we use /usr/local
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

rm -f /tmp/pi-controller-reset.patch
EOF
