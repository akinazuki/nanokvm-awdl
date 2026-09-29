#!/bin/sh
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${OUT:-$REPO/out}
OWL_REF=${OWL_REF:-da255a7}
mkdir -p "$OUT"

export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture armhf
apt-get update -qq
apt-get install -y -qq git cmake make ca-certificates pkg-config \
  gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf \
  libpcap-dev:armhf libev-dev:armhf libnl-3-dev:armhf libnl-genl-3-dev:armhf libnl-route-3-dev:armhf >/dev/null

cat > /tmp/armhf.cmake <<'T'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)
set(CMAKE_FIND_ROOT_PATH /usr/arm-linux-gnueabihf /usr/lib/arm-linux-gnueabihf)
set(CMAKE_LIBRARY_ARCHITECTURE arm-linux-gnueabihf)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
T

SRC=/tmp/owl
rm -rf "$SRC"
git clone https://github.com/seemoo-lab/owl "$SRC"
git -C "$SRC" checkout -q "$OWL_REF"
git -C "$SRC" submodule update --init --recursive --depth 1
git -C "$SRC" apply "$REPO/patches/owl-nanokvm.patch"

rm -rf /tmp/owl-build && mkdir /tmp/owl-build && cd /tmp/owl-build
cmake "$SRC" -DCMAKE_TOOLCHAIN_FILE=/tmp/armhf.cmake -DCMAKE_BUILD_TYPE=Release \
  -Dev_LIBRARY=/usr/lib/arm-linux-gnueabihf/libev.a -DCMAKE_C_STANDARD_LIBRARIES=-lm >/dev/null
make -j"$(nproc)" owl
arm-linux-gnueabihf-strip daemon/owl
cp daemon/owl "$OUT/owl"
arm-linux-gnueabihf-readelf -d daemon/owl | grep NEEDED
ls -l "$OUT/owl"
