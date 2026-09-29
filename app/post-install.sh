#!/bin/bash
set -e
DEST=/opt/nanokvm-awdl
SRC="${NANOKVM_APP_DIR:-.}/deps"

KO_VM=$(strings "$SRC/aic8800_fdrv.ko" | grep -m1 '^vermagic=' | cut -d= -f2-)
if ! echo "$KO_VM" | grep -q "$(uname -r)"; then
  echo "ERROR: driver vermagic [$KO_VM] does not match kernel $(uname -r); refusing to install."
  exit 1
fi

mkdir -p "$DEST"
cp "$SRC/aic8800_fdrv.ko" "$SRC/owl" "$SRC/owl_up.sh" "$SRC/kvm_awdl_up.sh" "$DEST/"
chmod +x "$DEST/owl" "$DEST"/*.sh
echo "AWDL deps installed to $DEST (kernel $(uname -r) OK)"
