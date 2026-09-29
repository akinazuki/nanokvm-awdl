#!/bin/sh
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${OUT:-$REPO/out}
STAGE=$(mktemp -d)
APP=$STAGE/awdl-toggle

for f in owl aic8800_fdrv.ko; do
  [ -f "$OUT/$f" ] || { echo "missing build artifact: $OUT/$f" >&2; exit 1; }
done

mkdir -p "$APP/deps"
cp "$REPO/app/app.json" "$REPO/app/main.py" "$REPO/app/post-install.sh" "$APP/"
cp "$REPO/scripts/owl_up.sh" "$REPO/scripts/kvm_awdl_up.sh" "$APP/deps/"
cp "$OUT/owl" "$OUT/aic8800_fdrv.ko" "$APP/deps/"
chmod +x "$APP/post-install.sh" "$APP/deps/owl" "$APP/deps/"*.sh

( cd "$STAGE" && zip -qr "$OUT/awdl-toggle.zip" awdl-toggle )
rm -rf "$STAGE"
unzip -l "$OUT/awdl-toggle.zip"
