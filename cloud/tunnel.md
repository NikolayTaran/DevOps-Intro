# Bonus — Cloudflare quick tunnel + latency comparison

**Date:** 2026-10-07 · `cloudflared` `2026.10.0` (Windows binary on the laptop, `.deb` in the codespace)

## 1. Goal vs reality

The lab wants a quick tunnel from the **local machine**. From this residential
network (RU ISP), that proved impossible — not by misconfiguration, but because
the ISP/DPI actively resets Cloudflare tunnel **edge connections (port 7844)**.
Six logged attempts across two networks and both protocols:

| # | Origin network | Protocol | Pre-checks | Outcome |
|---|---|---|---|---|
| 1 | laptop, home Wi-Fi + VPN | quic | UDP FAIL | dial fails: `timeout: no recent network activity`, endless retry |
| 2 | laptop, home Wi-Fi + VPN | http2 | TCP FAIL* | registration OK, **served traffic ~2.5 min**, then `Lost connection with the edge` → `connection with edge closed` |
| 3 | laptop, home Wi-Fi, VPN off | quic | UDP+TCP FAIL | dial fails, same as #1 |
| 4 | laptop, home Wi-Fi, VPN off | http2 | **ALL PASS** (once) | registered, edge closed after **~19 s**, process exits |
| 5 | laptop, phone LTE hotspot | quic | **ALL PASS** | registration timeout: `control stream error: context deadline exceeded` |
| 6 | laptop, phone LTE hotspot | http2 | — | `api.trycloudflare.com` POST intermittently times out; no window ≥ 90 s |

\* pre-checks are advisory: with VPN+http2 the dial actually got through and registered.

Typical log fingerprints (full console output preserved in the chat transcript):

```text
ERR Failed to dial a quic connection error="failed to dial to edge with quic:
    timeout: no recent network activity"
ERR Serve tunnel error error="connection with edge closed"
failed to request quick Tunnel: Post "https://api.trycloudflare.com/tunnel":
    context deadline exceeded
```

## 2. Adaptation (documented deviation)

The tunnel **origin was moved into the Codespace** (Azure US datacenter — no DPI
on the path). This keeps the bonus honest and actually improves the experiment:

- **Same image, same container** as Task 2 (`quicknotes:v0.1.0` on `:8080`) → the
  comparison below isolates the *ingress path*, not the origin.
- The lab hint *"measure from a different machine than the one running the
  tunnel"* is satisfied: tunnel origin = codespace VM; measurement clients =
  residential laptop + a phone on LTE.
- Registration from Azure succeeded **on the first attempt** and stayed stable for
  the whole measurement session (screenshot `submissions/screenshots/lab10-7.png`).

## 3. The working tunnel

```text
URL: https://compromise-cayman-reviewing-telephony.trycloudflare.com   (ephemeral)
$ cloudflared tunnel --url http://localhost:8080 --protocol http2
INF Registered tunnel connection connIndex=0
$ curl -s https://compromise-cayman-reviewing-telephony.trycloudflare.com/health
{"notes":4,"status":"ok"}
```

Verified from **outside** networks:

- laptop (residential ISP, client-side only — port 443, no 7844 involved): same JSON —
  browser screenshot `submissions/screenshots/lab10-5.png`
- **phone on LTE** (different carrier network): `{"notes":4,"status":"ok"}`, verified
  live during the session

(For completeness: the earlier laptop-origin attempt also produced a registered
quick tunnel and its banner — screenshot `submissions/screenshots/lab10-6.png` —
but its edge connection was killed by the ISP before it could serve.)

## 4. Latency comparison (warm `GET /health`, n=50, measured from the residential client)

```
TUNNEL    n=50 p50=0.321 p95=0.667 min=0.235 max=0.747
CODESPACE n=50 p50=0.503 p95=0.708 min=0.292 max=1.752
```

| Metric | Codespaces forwarding (app.github.dev) | Cloudflare tunnel (trycloudflare.com) |
|---|---:|---:|
| p50 | 0.503 s | **0.321 s** |
| p95 | 0.708 s | **0.667 s** |
| min | 0.292 s | 0.235 s |
| max | 1.752 s | 0.747 s |

**Reading:** the tunnel path is not only faster on p50, it is *tighter* — the
GitHub codespace gateway shows occasional ~1.7 s outliers. Cloudflare anycast
edge + a direct edge↔Azure-origin leg beats the `app.github.dev` gateway for
this workload. (Measurement tool: PowerShell `curl.exe` loop, 50 sequential
requests, `%{time_total}` — the laptop has no `hyperfine`/`wrk`.)

## 5. Honest limitations

- Quick-tunnel URLs are **ephemeral**: the URL above is dead by the time this is read (by design).
- Single measurement session, one network; no repeated campaigns.
- The origin deviation (§2) is deliberate and documented; the client-side network conditions (residential RU ISP) are part of the recorded evidence.
