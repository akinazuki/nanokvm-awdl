#!/bin/sh
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
MACSUF=$(cat /sys/class/net/wlan0/address 2>/dev/null | tr -d : | tail -c 5)
OWL_NAME="${OWL_NAME:-NanoKVM-${MACSUF}}"
pkill -x owl; sleep 1
if ! grep -q rwnx_start_monitor_if_xmit /proc/kallsyms; then
  kill $(cat /dev/shm/tmp/wifi/wpa.pid 2>/dev/null) 2>/dev/null; pkill -f "wpa_supplicant.*wlan0"; sleep 1
  rmmod aic8800_fdrv && insmod "$HERE/aic8800_fdrv.ko" auto_reply=1 aicwf_dbg_level=0
  w=0; while ! ip link show wlan0 >/dev/null 2>&1 && [ $w -lt 50 ]; do sleep 0.2; w=$((w+1)); done
fi
ip link set wlan0 down; iw dev wlan0 set type monitor; iw dev wlan0 set monitor active control otherbss; ip link set wlan0 up
nohup "$HERE/owl" -i wlan0 -c ${1:-44} -H ${OWL_METRIC:+-M $OWL_METRIC} -A "${OWL_ADVERTISE:-${OWL_NAME},_nanokvm,443,scheme=https}" > owl_up.log 2>&1 &
sleep 5
iw dev wlan0 info | grep -E "type|channel"; ip -br link show awdl0
