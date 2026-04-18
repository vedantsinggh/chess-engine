#!/bin/sh

set -e

if [ ! -d "stockfish/" ]; then
    git clone https://github.com/official-stockfish/Stockfish || exit 1
    mv Stockfish stockfish || exit 1
else
    exit 1
fi

cd stockfish/src || exit 1

make -j profile-build ARCH=native || exit 1  

if [ -f ./stockfish ]; then
    sudo cp -f ./stockfish /usr/local/lib/ || exit 1
else
    exit 1
fi

# cd engine || exit 1

# mkdir -p build
# cd build

# cmake .. || exit 1

# make || exit 1

# if [ -f ./libengine.so ]; then
#     sudo cp -f ./libengine.so /usr/local/lib/ || exit 1
# else 
#     exit 1
# fi
