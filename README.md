# nanokvm-awdl

Connect to NanoKVM Go over AWDL—the wireless technology behind AirDrop—from
compatible devices. No Wi-Fi pairing required.

## Install

Download `awdl-toggle.zip` from Releases and upload it in the NanoKVM web UI:
**Application Center → custom app**.

## Use

Tap the touchscreen button to start or stop AWDL. On a Mac, download `awdlkvm-macos.zip`
from Releases and run `awdlkvm`—it finds the KVM over AWDL and opens its web UI in your
browser, no Wi-Fi pairing. See [`mac/awdlkvm`](mac/awdlkvm) for details.

## How it works

The app bundles the OWL AWDL daemon and a patched Wi-Fi driver with monitor-mode
packet injection. Together, they establish a direct wireless link and carry
IPv6 traffic over the `awdl0` interface.
