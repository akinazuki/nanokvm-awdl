#!/usr/bin/env python3

import subprocess

from appbase import AppContext, BLACK, GRAY, GREEN, ORANGE, RED, Rect, WHITE, app

SCRIPT = "/opt/nanokvm-awdl/kvm_awdl_up.sh"


def owl_running() -> bool:
    return subprocess.run(["pgrep", "-x", "owl"], capture_output=True).returncode == 0


def kvm_name() -> str:
    try:
        mac = open("/sys/class/net/wlan0/address").read().strip().replace(":", "")
        return "NanoKVM-" + mac[-4:]
    except Exception:
        return "NanoKVM"


@app()
def main(ctx: AppContext) -> None:
    r = ctx.fb.rotate
    x0 = 14 if r == 0 else 0
    x1 = ctx.width - (14 if r == 180 else 0)
    y0 = 14 if r == 270 else 0
    y1 = ctx.height - (14 if r == 90 else 0)
    cx = (x0 + x1) // 2
    uh = y1 - y0

    channel = ctx.env.get("CHANNEL", "44")
    installed = subprocess.run(["test", "-x", SCRIPT]).returncode == 0
    state = {"phase": "on" if owl_running() else "off", "proc": None}

    bh = 50
    button = Rect(x0 + 22, y1 - 14 - bh, (x1 - x0) - 44, bh)

    def start() -> None:
        state["proc"] = subprocess.Popen(
            ["sh", SCRIPT, channel], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        state["phase"] = "starting"

    def stop() -> None:
        state["proc"] = subprocess.Popen(
            ["sh", "-c", "pkill -x owl; pkill -f 'avahi-publish-service NanoKVM'"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        state["phase"] = "stopping"

    def on_tap(x: int, y: int) -> None:
        if not installed or state["phase"] in ("starting", "stopping"):
            return
        if button.contains(x, y):
            stop() if state["phase"] == "on" else start()

    def tick(dt: float) -> None:
        if state["phase"] == "starting" and owl_running():
            state["phase"] = "on"
        elif state["phase"] == "stopping" and not owl_running():
            state["phase"] = "off"
        elif state["phase"] in ("on", "off"):
            state["phase"] = "on" if owl_running() else "off"

        fb = ctx.fb
        fb.clear(BLACK)
        fb.text_center(cx, y0 + 16, "AWDL", WHITE, 2)

        if not installed:
            fb.text_center(cx, y0 + uh // 2 - 8, "not installed", RED, 1)
            fb.text_center(cx, y0 + uh // 2 + 10, "run install.sh", GRAY, 1)
            return

        mid = y0 + int(uh * 0.34)
        sub = y0 + int(uh * 0.60)
        phase = state["phase"]
        if phase == "on":
            fb.text_center(cx, mid, "ON", GREEN, 4)
            fb.text_center(cx, sub, kvm_name(), WHITE, 1)
            fb.text_center(cx, sub + 18, "ch " + channel, GRAY, 1)
            ctx.button(button, "STOP", RED)
        elif phase == "off":
            fb.text_center(cx, mid, "OFF", GRAY, 4)
            fb.text_center(cx, sub, "Wi-Fi normal", GRAY, 1)
            ctx.button(button, "START", GREEN)
        else:
            fb.text_center(cx, mid, "...", ORANGE, 4)
            fb.text_center(cx, sub, phase, ORANGE, 1)

    ctx.run(tick, fps=8, on_tap=on_tap)


if __name__ == "__main__":
    main()
