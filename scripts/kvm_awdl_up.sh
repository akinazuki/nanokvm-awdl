#!/bin/sh
HERE=$(cd "$(dirname "$0")" && pwd)
sh "$HERE/owl_up.sh" "${1:-44}" >/dev/null
for p in $(pgrep -f "avahi-publish-service NanoKVM"); do kill $p 2>/dev/null; done
NAME="NanoKVM-$(cat /sys/class/net/wlan0/address | tr -d : | tail -c 5)"
nohup avahi-publish-service "$NAME" _nanokvm._tcp 443 scheme=https > /tmp/nanokvm_pub.log 2>&1 &
sleep 2
MAC=$(cat /sys/class/net/wlan0/address 2>/dev/null)
ADDR=$(ip -6 addr show awdl0 2>/dev/null | awk '/scope link/{print $2}' | cut -d/ -f1)
echo "AWDL up; ${NAME}._nanokvm._tcp:443 advertised (OWL AWDL TLVs + avahi)"
echo "KVM awdl0 address (stable): ${ADDR}%awdl0"
