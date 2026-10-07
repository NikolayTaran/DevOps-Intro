# Option B — GitHub Codespaces: the deployed environment

**Date:** 2026-10-07 · **Codespace:** `crispy-guide-4x945xgrr7wh7wvq` ("crispy guide")
**Branch:** `feature/lab10` · **Region:** Azure US (datacenter) · **Image:** `ghcr.io/nikolaytaran/devops-intro/quicknotes:v0.1.0`

## Configuration (checked-in `.devcontainer/devcontainer.json`)

- Base image: `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` (no project toolchain needed — the app runs as a container)
- Feature: `ghcr.io/devcontainers/features/docker-in-docker:2` — Docker daemon inside the codespace
- `forwardPorts: [8080]` + `portsAttributes` (label `QuickNotes`, `onAutoForward: notify`)
- `postStartCommand`: on every start pulls the released image from Task 1 and runs it:
  `docker pull ghcr.io/.../quicknotes:v0.1.0 && docker rm -f quicknotes; docker run -d --name quicknotes -p 8080:8080 -e ADDR=:8080 -e PORT=8080 ...`

The codespace therefore always serves **the exact artifact Task 1 released**, not a re-build.

## Public URL

```text
https://crispy-guide-4x945xgrr7wh7wvq-8080.app.github.dev
```

Two manual steps per start (GitHub defaults forwarded ports to **Private** for security):

1. Ports tab → port `8080` → visibility **Public** — screenshot `submissions/screenshots/lab10-3.png`
2. Verify from the laptop (screenshot `submissions/screenshots/lab10-4.png`):

```
$ curl -v https://crispy-guide-4x945xgrr7wh7wvq-8080.app.github.dev/health
* ALPN: server accepted http/1.1 · using HTTP/1.x
< HTTP/1.1 200 OK
< Content-Type: application/json
< Content-Length: 26
* schannel: remote party requests renegotiation (repeated)
{"notes":4,"status":"ok"}
```

(Windows `curl` 8.21.0/schannel: GitHub's relay keeps this endpoint on HTTP/1.1 and renegotiates TLS — see `lab10-4.png`. While the port is Private the same curl hangs into connection timeout — that was the first debugging lesson.)

## Measurements

Client: residential laptop (Windows 11, `curl`/`curl.exe`), separate network path from the origin.

| Metric | Result |
|---|---|
| Warm p50 (5× `GET /health` in a row) | **0.42 s** (samples: 0.655, 0.449, 0.372, 0.412, 0.422) |
| Stopped codespace (3 probes) | **HTTP 502** in 0.59 / 0.82 / 0.72 s — does **not** self-wake |
| Cold start, cycle 1 (stop → start → 200) | **≈ 5 min** total — inflated by resuming the codespace through a browser over a slow VPN link (honest annotation, not platform time) |
| Cold start, cycles 2–3 | **≈ 30–40 s** stop → first `200` (0.55 / 0.62 s once the container is up) |
| Manual `docker run` of the ghcr image inside the codespace | **≈ 2 s** (layers cached on the DinD daemon) |
| Note persistence across restart | POSTed note `lab10-persist` (id 5) **gone** after restart — only 4 seed notes remain (DinD container + writable layer recreated) |

## Scale-to-zero analogy (what was actually observed)

Render/HF free tiers wake **on the next request**; a stopped codespace never does —
the `502` comes from GitHub's edge, and "waking" means a human clicking Resume
(or `gh codespace start` / reopening the editor). Measured above.
