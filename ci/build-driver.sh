#!/bin/bash
set -euo pipefail
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${OUT:-$REPO/out}
W=${W:-/tmp/kbuild}
KERN_REPO=${KERN_REPO:-https://github.com/akinazuki/maix_ax620e_sdk_kernel}
KERN_BRANCH=${KERN_BRANCH:-main}
TC_NAME=gcc-arm-10.3-2021.07-$(uname -m)-arm-none-linux-gnueabihf
TC=${TC_DIR:-/opt/toolchain}/$TC_NAME
KSRC=$W/kern/linux/linux-4.19.125
KOUT=$W/kout
DRV=$W/aic8800_mon
CC_PREFIX=arm-none-linux-gnueabihf-
mkdir -p "$OUT" "$W"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq make gcc bc bison flex libssl-dev libelf-dev patch xz-utils wget git ca-certificates python3 rsync >/dev/null

if [ ! -x "$TC/bin/${CC_PREFIX}gcc" ]; then
  mkdir -p "$(dirname "$TC")"
  wget -q -O /tmp/tc.tar.xz "https://developer.arm.com/-/media/Files/downloads/gnu-a/10.3-2021.07/binrel/$TC_NAME.tar.xz"
  tar -C "$(dirname "$TC")" -xf /tmp/tc.tar.xz
fi
export PATH=$TC/bin:$PATH
${CC_PREFIX}gcc --version | head -1

if [ ! -f "$KSRC/Makefile" ]; then
  rm -rf "$W/kern"; mkdir -p "$W/kern"; cd "$W/kern"
  git init -q
  git remote add origin "$KERN_REPO"
  git config core.sparseCheckout true
  git sparse-checkout init --cone
  git sparse-checkout set linux/linux-4.19.125
  git fetch -q --depth 1 --filter=blob:none origin "$KERN_BRANCH"
  git checkout -q FETCH_HEAD
fi

mkdir -p "$KOUT"
if [ ! -f "$KOUT/include/generated/utsrelease.h" ]; then
  make -C "$KSRC" O="$KOUT" ARCH=arm CROSS_COMPILE=$CC_PREFIX LOCALVERSION= \
       axera_AX620Q_emmc_arm32_k419_sipeed_nanoagent_defconfig
  make -C "$KSRC" O="$KOUT" ARCH=arm CROSS_COMPILE=$CC_PREFIX LOCALVERSION= -j"$(nproc)" modules_prepare
fi
echo "utsrelease: $(cat "$KOUT/include/generated/utsrelease.h")"

rsync -a --delete "$KSRC/drivers/net/wireless/aic8800/" "$DRV/"
patch -p1 -d "$DRV" < "$REPO/patches/aic8800_fdrv-monitor-injection.patch"
grep -nE "^CONFIG_RWNX_MON_(XMIT|RXFILTER|DATA)" "$DRV/aic8800_fdrv/Makefile"

make -C "$KOUT" ARCH=arm CROSS_COMPILE=$CC_PREFIX LOCALVERSION= M="$DRV/aic8800_bsp" -j"$(nproc)" modules
cp "$DRV/aic8800_bsp/Module.symvers" "$DRV/aic8800_fdrv/" 2>/dev/null || true
make -C "$KOUT" ARCH=arm CROSS_COMPILE=$CC_PREFIX LOCALVERSION= M="$DRV/aic8800_fdrv" \
     KBUILD_EXTRA_SYMBOLS="$DRV/aic8800_bsp/Module.symvers" -j"$(nproc)" modules

cp "$DRV/aic8800_fdrv/aic8800_fdrv.ko" "$OUT/"
${CC_PREFIX}strip --strip-debug "$OUT/aic8800_fdrv.ko"
strings "$OUT/aic8800_fdrv.ko" | grep -E "^vermagic=|start_monitor_if_xmit" | sort -u
ls -l "$OUT/aic8800_fdrv.ko"
