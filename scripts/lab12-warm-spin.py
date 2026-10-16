#!/usr/bin/env python3
"""Lab 12 — warm-latency measurement for the Spin /time endpoint.

Keep-alive HTTP loop (one persistent connection), same protocol as the
Docker-side PowerShell script (scripts/lab12-docker-perf.ps1) so both
platforms are measured with identical semantics:
  5 warmup requests, then 50 measured; p50/p95 nearest-rank.

Usage: lab12-warm-spin.py [url] [warmup] [runs]
"""
import http.client
import json
import socket
import statistics
import sys
import time

URL = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1:33123"
WARMUP = int(sys.argv[2]) if len(sys.argv) > 2 else 5
RUNS = int(sys.argv[3]) if len(sys.argv) > 3 else 50

host, port = URL.split(":")
port = int(port)

conn = http.client.HTTPConnection(host, port, timeout=5)

# warmup
for _ in range(WARMUP):
    conn.request("GET", "/time")
    r = conn.getresponse()
    r.read()
    if r.status != 200:
        raise SystemExit(f"warmup: unexpected status {r.status}")

times = []
for _ in range(RUNS):
    t0 = time.perf_counter()
    conn.request("GET", "/time")
    r = conn.getresponse()
    body = r.read()
    t1 = time.perf_counter()
    if r.status != 200:
        raise SystemExit(f"measured run: unexpected status {r.status}")
    times.append((t1 - t0) * 1000.0)

conn.close()
srt = sorted(times)
# nearest-rank percentiles, same convention as the Docker-side script
p50 = srt[int(RUNS * 0.50) - 1]
p95 = srt[int(RUNS * 0.95) - 1]
print(json.dumps({
    "url": URL,
    "warmup": WARMUP,
    "runs": RUNS,
    "p50_ms": round(p50, 3),
    "p95_ms": round(p95, 3),
    "mean_ms": round(statistics.mean(times), 3),
    "min_ms": round(min(times), 3),
    "max_ms": round(max(times), 3),
    "body": body.decode(),
}, indent=2))
