#!/bin/bash
# A starter pack of instruments, sound effects, etc.
# This script is intended to be executed on the pistomp itself

pushd /home/pistomp/data/user-files >/dev/null

pushd 'SFZ Instruments' >/dev/null
    wget https://freepats.zenvoid.org/Piano/UprightPianoKW/UprightPianoKW-SFZ-20220221.7z
    7z x UprightPianoKW-SFZ-20220221.7z
    rm UprightPianoKW-SFZ-20220221.7z

    wget https://www.williamkage.com/snes_soundfonts/sfz/chrono_trigger_samples_sfz.zip
    unzip chrono_trigger_samples_sfz.zip -d .
    rm chrono_trigger_samples_sfz.zip

    wget https://tssf.gamemusic.ca/Remakes/Zelda64Stuff/oot2dsf2.zip
    unzip oot2dsf2.zip -d .
    rm oot2dsf2.zip
popd >/dev/null

pushd 'SF2 Instruments' >/dev/null
    wget https://freepats.zenvoid.org/Piano/YDP-GrandPiano/YDP-GrandPiano-SF2-20160804.tar.bz2
    tar xjf YDP-GrandPiano-SF2-20160804.tar.bz2
    rm YDP-GrandPiano-SF2-20160804.tar.bz2

    wget https://www.williamkage.com/snes_soundfonts/chrono_trigger_soundfont.zip
    unzip chrono_trigger_soundfont.zip -d .
    rm chrono_trigger_soundfont.zip

    wget https://tssf.gamemusic.ca/Remakes/Zelda64Stuff/zelda3sf2.zip
    unzip zelda3sf2.zip -d .
    rm zelda3sf2.zip
popd >/dev/null

popd >/dev/null