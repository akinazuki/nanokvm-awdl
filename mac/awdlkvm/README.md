# awdlkvm

Reach a NanoKVM's web UI over AWDL—the wireless technology behind AirDrop—from a
Mac. No Wi-Fi pairing, router, or cable.

## Build

```sh
swift build -c release      # -> .build/release/awdlkvm
```

## Use

Start AWDL on the KVM with the touchscreen app. Then on the Mac:

```sh
awdlkvm                       # discover over AWDL and open the web UI
awdlkvm --list                # list nearby NanoKVMs
awdlkvm --name NanoKVM-98cd   # pick one by name, and remember it
```

awdlkvm opens `https://localhost:8443/` in your browser. Run `awdlkvm --help` for all
options; for several KVMs, give each its own `--name` and `--port`.

## How it works

awdlkvm runs a loopback proxy: browser → `https://localhost:8443` → `awdl0` → KVM
`:443`. macOS only routes awdl0 connections that target a Bonjour service endpoint, so
awdlkvm connects via the KVM's `_nanokvm._tcp` service (OWL advertises it in AWDL
frames); `--mac`/`--host` are best-effort raw-address fallbacks.
