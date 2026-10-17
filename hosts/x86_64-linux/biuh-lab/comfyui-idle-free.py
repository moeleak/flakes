#!/usr/bin/env python3
"""Unload ComfyUI's models from VRAM once it has been idle for IDLE_S seconds.

POST /free with unload_models moves the models to RAM (ComfyUI keeps them there), so the next run reloads them
quickly instead of reading the disk.  Idle means: nothing queued or running, and the last finished run ended
IDLE_S ago.  Runs on the host beside the comfyui-cu130 container; no container restart is needed.
"""
import json
import os
import time
import urllib.request

URL = os.environ.get("COMFY_URL", "http://127.0.0.1:8188")
IDLE_S = int(os.environ.get("IDLE_S", "300"))
POLL_S = int(os.environ.get("POLL_S", "30"))
MIN_HELD = int(os.environ.get("MIN_HELD_MIB", "1024")) * 2**20   # below this ComfyUI holds no model worth freeing


def get(path):
    with urllib.request.urlopen(URL + path, timeout=10) as r:
        return json.load(r)


def last_activity():
    q = get("/queue")
    if q["queue_running"] or q["queue_pending"]:
        return time.time()
    h = get("/history?max_items=1")
    ts = [m[1].get("timestamp", 0) for v in h.values() for m in v.get("status", {}).get("messages", [])]
    return max(ts, default=0) / 1000


last_err = None
while True:
    try:
        held = get("/system_stats")["devices"][0]["torch_vram_total"]
        if held >= MIN_HELD and time.time() - last_activity() >= IDLE_S:
            req = urllib.request.Request(URL + "/free", data=b'{"unload_models": true}', method="POST",
                                         headers={"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=10).close()
            print(f"idle for {IDLE_S}s or more: unloaded models, {held / 2**20:.0f} MiB of VRAM given back", flush=True)
        last_err = None
    except Exception as e:      # ComfyUI restarting or down: say so once, keep polling
        if str(e) != last_err:
            print(f"cannot reach ComfyUI: {e}", flush=True)
            last_err = str(e)
    time.sleep(POLL_S)
