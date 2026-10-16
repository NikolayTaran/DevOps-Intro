#!/usr/bin/env python3
"""Lab 12 — cold-start measurement for the Spin /time endpoint.

For each sample: make sure no spin process is running, start `spin up`,
poll GET /time until the first HTTP 200, and record the wall time from
process start to first successful response. 7 samples; reports all values
plus p50 (nearest-rank). Same protocol as the Docker-side PowerShell
script (scripts/lab12-docker-perf.ps1).

Usage: lab12-coldstart-spin.py [workdir] [listen_port] [samples]
"""
import http.client
import json
import statistics
import subprocess
import sys
import time

WORKDIR = sys.argv[1] if len(sys.argv) > 1 else "/home/z/fork12/wasm"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 33123
SAMPLES = int(sys.argv[3]) if len(sys.argv) > 3 else 7


def kill_spin():
    subprocess.run(["pkill", "-f", "spin up"], check=False)
    time.sleep(0.3)


def one_sample():
    kill_spin()
    t0 = time.perf_counter()
    proc = subprocess.Popen(
        ["spin", "up", "--listen", f"127.0.0.1:{PORT}"],
        cwd=WORKDIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    while True:
        try:
            conn = http.client.HTTPConnection("127.0.0.1", PORT, timeout=1)
            conn.request("GET", "/time")
            r = conn.getresponse()
            r.read()
            conn.close()
            if r.status == 200:
                t1 = time.perf_counter()
                return (t1 - t0) * 1000.0
        except OSError:
            pass
        if proc.poll() is not None:
            raise SystemExit("spin up exited before serving /time")
        time.sleep(0.002)


samples = [one_sample() for _ in range(SAMPLES)]
kill_spin()
srt = sorted(samples)
p50 = srt[int(SAMPLES * 0.50) - 1] if SAMPLES % 2 else (srt[SAMPLES // 2 - 1])
print(json.dumps({
    "workdir": WORKDIR,
    "port": PORT,
    "samples": SAMPLES,
    "p50_ms": round(p50, 1),
    "mean_ms": round(statistics.mean(samples), 1),
    "min_ms": round(min(samples), 1),
    "max_ms": round(max(samples), 1),
    "all_ms": [round(s, 1) for s in samples],
}, indent=2))
