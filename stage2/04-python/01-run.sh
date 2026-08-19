#!/bin/bash -e

echo "Installing Python PIP packages"
on_chroot << EOF

# raspberrypi-sys-mods ships a PEP 668 EXTERNALLY-MANAGED marker that blocks
# system-wide pip. It is dpkg-diverted (original preserved at *.orig) so
# rm -rf only removes the diverted copy and apt upgrades resurrect it.
# Use pip's --break-system-packages escape hatch instead — upgrade-proof.
# (mod-ui's venv removes its own copy in debpkgs/mod-ui/debian/rules.)

# System-wide pip packages for services that use --system-site-packages venvs.
# tornado is NOT installed here — mod-ui needs tornado==4.3 (incompatible with
# Python 3.13) and gets its own Python 3.11 venv in debpkgs/mod-ui/debian/rules.
# pi-stomp and pistomp-recovery use uv venvs with their own uv.lock — don't
# duplicate their deps here.
pip3 install --break-system-packages flask unicategories   # browsepy (--system-site-packages, --no-deps)
pip3 install --break-system-packages netifaces2            # touchosc2midi

EOF
echo "Done installing PIP packages"
