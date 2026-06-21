#!/bin/bash -e

echo "Installing Python PIP packages"
on_chroot << EOF

rm -rf /usr/lib/python3/dist-packages/EXTERNALLY-MANAGED
rm -rf /usr/lib/python3.13/EXTERNALLY-MANAGED

# Core runtime deps for pi-stomp and supporting services.
# tornado is NOT installed here — mod-ui needs tornado==4.3 which is
# incompatible with Python 3.13; it gets its own Python 3.11 venv (see 02-run.sh).
pip3 install pyserial pycryptodomex aggdraw
pip3 install JACK-Client
pip3 install flask unicategories
pip3 install pyaml
pip3 install netifaces2
pip3 install mido docopt
pip3 install pyliblo3

EOF
echo "Done installing PIP packages"
