# Lab 10 — Cloud Deploy: QuickNotes to a Real Registry + Public URL

**Student:** NikolayTaran (na.taranvrn@gmail.com)
**Fork:** https://github.com/NikolayTaran/DevOps-Intro
**Branch:** `feature/lab10` (cut from `feature/lab9`)
**Host:** Windows 11 laptop (client side) · GitHub Codespaces (origin side)
**Image:** `ghcr.io/nikolaytaran/devops-intro/quicknotes:v0.1.0` (public)
**Date:** 2026-10-07

---

## 0. What the lab requires (vs what was delivered)

The lab text names Hugging Face Spaces; the course's pinned update replaced the
hosted platform with **Render (Option A) → Codespaces (Option B fallback)** after
Render started demanding card verification. This submission follows the pinned
update: Option A was genuinely attempted and is documented, Option B is fully
delivered and measured.

| # | Requirement | Where |
|---|-------------|-------|
| T1.1 | Release workflow: tag `v*` → build → ghcr.io (`:version` + `:latest`) | §1.1, `.github/workflows/release.yml` |
| T1.2 | Actions pinned by SHA, least-privilege permissions | §1.1 |
| T1.3 | Public image, clean anonymous pull | §1.2 |
| T1.4 | Green CI release-run URL | §1.2 |
| T1.5 | Design questions a–c | §1.3 |
| T2.1 | Option A attempted (Render) | §2.1, `cloud/render.md` |
| T2.2 | Option B delivered (Codespaces), public URL serves JSON | §2.2, `cloud/codespaces.md` |
| T2.3 | Scale-to-zero observed; cold-vs-warm measured | §2.3 |
| T2.4 | Design questions d–f (adapted to Option B) | §2.4 |
| B.1 | Quick tunnel serves QuickNotes publicly | §3.2, `cloud/tunnel.md` |
| B.2 | Verified from a different network (phone, LTE) | §3.2 |
| B.3 | Warm p50/p95 comparison table | §3.3 |
| B.4 | Design questions g–i | §3.4 |

Screenshots: `submissions/screenshots/lab10-{3,4,5,6,7}.png`.

---

## 1. Task 1 — CI push to ghcr.io (6 pts)

### 1.1 Workflow (`.github/workflows/release.yml`)

- **Trigger:** `push` of tags `v*`
- **Runner:** `ubuntu-24.04` (pinned, not `ubuntu-latest`)
- **Permissions:** `contents: read` + `packages: write` only
- **Actions pinned to 40-char SHAs:** `checkout@11bd7190…` (v4.2.2), `setup-buildx@e468171a…` (v3.11.1), `login-action@74a5d142…` (v3.4.0), `build-push-action@26343531…` (v6.18.0)
- **Image:** `ghcr.io/nikolaytaran/devops-intro/quicknotes:{v0.1.0, latest}`, context `./app`, platform `linux/amd64`, GHA layer cache
- Image name lowercased before it reaches ghcr.io (registry rejects uppercase paths)
- **Optional Render deploy hook:** step reads secret `RENDER_DEPLOY_HOOK`; when unset it prints a skip line and `exit 0` — the Codespaces fallback needs no workflow changes. `imgURL` is URL-encoded (`%2F`, `%3A`) and appended correctly whether the hook URL already contains `?` or not.

### 1.2 Evidence

| Item | Value |
|---|---|
| Release run (green) | https://github.com/NikolayTaran/DevOps-Intro/actions/runs/37677515891 |
| Registry URL | `ghcr.io/nikolaytaran/devops-intro/quicknotes:v0.1.0` (+ `:latest`) |
| Package visibility | **Public** (flipped once in the GH UI after first push) |
| Clean pull, no auth | `docker pull` succeeded; `Digest: sha256:9dfa0685…` |

### 1.3 Design questions

**a) OIDC vs `GITHUB_TOKEN`.** For a same-repo push to ghcr.io, `GITHUB_TOKEN` + `packages: write` is the intended, sufficient mechanism. OIDC becomes the right tool when the pipeline must authenticate to a *different* trust domain — AWS ECR / GCP Artifact Registry / Azure ACR, or another org's registry: the workflow mints a short-lived, audience-bound token per run, so no long-lived cloud credentials ever sit in Actions secrets, and leaked-at-rest risk disappears. That is exactly what `GITHUB_TOKEN` cannot give: it is repo-scoped and static for the job's lifetime.

**b) Why ship `:latest` alongside `:v0.1.0`.** `:v0.1.0` is the immutable pin that rollbacks, SBOMs, and production manifests reference — it can never change under you. `:latest` is the mutable convenience pointer for humans and docs: `docker pull …/quicknotes:latest` always yields "whatever we currently call stable" without reading changelogs. You ship both; you *deploy* the immutable tag and treat `:latest` as a courtesy label.

**c) Why `packages: write` only.** Least privilege: the automatic job token can publish a package but cannot modify Actions secrets, deploy keys, branch protection, or other repositories. If the build is compromised (malicious dependency, poisoned cache), the blast radius is "attacker publishes a bad image" — recoverable and auditable — not "attacker owns the repository", which `write: all` would allow via secret exfiltration or workflow edits.

---

## 2. Task 2 — Deploy to a public URL (4 pts)

### 2.1 Option A — Render: attempted, blocked (cloud/render.md)

Form filled per the lab (image URL, Oregon, Free, `ADDR=:8080`, `PORT=8080`).
Render accepted the public image but required **card verification before the
service could be created**, including on the Free plan; Russian-issued cards are
rejected by the processor. Per the pinned update, switched to Option B.
Full attempt documented in `cloud/render.md`.

### 2.2 Option B — Codespaces: delivered (cloud/codespaces.md)

Checked-in `.devcontainer/devcontainer.json`:

- `base:ubuntu-24.04` + `docker-in-docker:2` feature
- `postStartCommand` pulls the **released** Task 1 image and runs it on `:8080` — the codespace serves the exact released artifact, not a rebuild
- `forwardPorts: [8080]`, port labeled `QuickNotes`

**Public URL:** `https://crispy-guide-4x945xgrr7wh7wvq-8080.app.github.dev`
(codespace `crispy-guide-4x945xgrr7wh7wvq`, port 8080 visibility **Public** — screenshot `lab10-3.png`)

```text
$ curl -v https://crispy-guide-4x945xgrr7wh7wvq-8080.app.github.dev/health
* ALPN: server accepted http/1.1 · using HTTP/1.x
< HTTP/1.1 200 OK
< Content-Type: application/json
< Content-Length: 26
* schannel: remote party requests renegotiation (repeated)
{"notes":4,"status":"ok"}
```
(Windows `curl` 8.21.0/schannel: GitHub's relay keeps this endpoint on HTTP/1.1 and renegotiates TLS — full output in screenshot `lab10-4.png`)

### 2.3 Scale-to-zero observation + latency

Client = residential laptop, separate network from the origin. One honest
annotation: the first cold-start cycle took ≈5 min *wall-clock*, but that
includes resuming the codespace through a browser over a slow VPN link — the
platform-controlled part of cycles 2–3 was 30–40 s.

| Metric | Result |
|---|---|
| Warm p50 (5× `GET /health`) | **0.42 s** (0.655 / 0.449 / 0.372 / 0.412 / 0.422) |
| Stopped codespace probes | **502** in 0.59 / 0.82 / 0.72 s — no self-wake |
| Cold cycle 1 (stop→start→200) | ≈ 5 min wall (VPN-annotated above) |
| Cold cycles 2–3 | ≈ 30–40 s; first `200` after container up: 0.55 / 0.62 s |
| `docker run` of ghcr image in codespace | ≈ 2 s (cached layers) |
| Note persistence | POSTed note `lab10-persist` **gone** after restart (DinD container + writable layer recreated; only 4 seed notes left) |

### 2.4 Design questions (adapted to Option B)

**d) Wake-on-request vs stopped dev VM.** Render/HF free tiers are hosting platforms: the edge proxy queues the request and re-instantiates the container — slow (tens of seconds), but the URL never fails. A stopped codespace is a dev VM, not a service: our probes got immediate **502** from GitHub's edge and it never woke by itself; "waking" means a human Resume. The platform optimizes interactive development (persistent disk, editor sessions) over request serving — hence wake = manual start, ≈30–40 s to first `200` (measured).

**e) Why the port must be declared.** The app binds `ADDR=:8080`; `forwardPorts: [8080]` in `devcontainer.json` makes forwarding deterministic instead of listen-time magic. The analog of HF's `app_port` (HF defaults to 7860 — a Gradio/Streamlit heritage; a non-default app port must be declared or the Space routes to nothing) is in Codespaces the pair *declaration + visibility*: GitHub forwards ports **Private** by default, so the manual flip to Public is a deliberate security decision, and our first `curl` timed out exactly because of it.

**f) Pull vs build inside the environment.** `postStartCommand` pulls the exact released digest: ≈2 s warm (cached layers), reproducible, and it exercises the very artifact Task 1 shipped — the deploy path tests what users actually run. Building the Dockerfile inside the Space/codespace needs the toolchain, pays the build every time (no layer cache), and can drift from the released image. The pull-side trade-off: it depends on the registry being up and the package staying public.

---

## 3. Bonus — Cloudflare quick tunnel (2 pts)

### 3.1 The obstacle, honestly

Six attempts to originate the tunnel from the laptop failed — RU residential ISP
DPI resets Cloudflare edge connections on port 7844 (QUIC dial timeouts; http2
registered but was killed after 19 s–2.5 min; the API itself intermittently
unreachable). Full attempt matrix + log fingerprints: `cloud/tunnel.md`.

### 3.2 Working tunnel + external verification

Origin moved into the Codespace (Azure, no DPI on path) — same image, same
container as §2, so the comparison below isolates the **ingress path**. The lab
hint "measure from a different machine than the tunnel host" is satisfied:
clients are the residential laptop and a phone on LTE.

```text
URL: https://compromise-cayman-reviewing-telephony.trycloudflare.com   (ephemeral)
$ curl -s https://compromise-cayman-reviewing-telephony.trycloudflare.com/health
{"notes":4,"status":"ok"}
```

- **Phone, LTE (different carrier network):** same JSON, verified live during the session
- Tunnel URL `/health` in a desktop browser (laptop) — screenshot `lab10-5.png`
- Codespace registration banner — screenshot `lab10-7.png`
- Earlier laptop-origin banner (registered, then killed by ISP) — screenshot `lab10-6.png`

### 3.3 Comparison table (warm `GET /health`, n=50, from the residential client)

| Metric | Codespaces forwarding (app.github.dev) | Cloudflare tunnel (trycloudflare.com) |
|---|---:|---:|
| p50 | 0.503 s | **0.321 s** |
| p95 | 0.708 s | **0.667 s** |
| min | 0.292 s | 0.235 s |
| max | 1.752 s | 0.747 s |

The tunnel is faster **and tighter**: the GitHub gateway shows occasional ~1.7 s
outliers, while the Cloudflare path (anycast edge + direct edge↔Azure leg) stays
under 0.75 s across all 50 samples. Tool: 50 sequential `curl.exe` requests,
`%{time_total}` (no `hyperfine`/`wrk` on the laptop).

### 3.4 Design questions

**g) "Really cloud"?** In a hosted Space/Render the compute runs in the provider's DC; in the classic tunnel setup the compute is *your laptop* and Cloudflare only proxies at the edge. "Really cloud" should mean: availability decoupled from your hardware, elastic capacity, someone else's 24/7 ops. By that test the classic tunnel is not cloud — when the laptop sleeps, the "cloud URL" dies. Our variant is a hybrid (origin = Azure VM), which dodges the laptop fragility but keeps two cloud-side caveats: ephemeral URL and no SLA. Users mostly feel the difference through availability, not through the URL's hostname.

**h) Latency dominator.** Hosted warm p50: TLS handshake + geographic RTT + free-tier noisy neighbors (the codespace gateway's 1.75 s max smells like a shared gateway queue). Tunnel warm: client→Cloudflare anycast edge is fast and nearby; the dominant leg is edge→origin — for a laptop origin, the home *uplink* upload; for our Azure origin, the datacenter↔POP link. The measurements agree: the tunnel path (0.321 p50) beats the GitHub gateway (0.503 p50) for this workload.

**i) When a tunnel is the right production pick — and when never.** Right: home labs and self-hosted services behind CGNAT/NAT without a public IP; on-prem/industrial systems that must not get a public ingress; temporary stakeholder/demo previews of a machine that already runs the service. Never: SLA'd production (quick tunnels explicitly carry no uptime guarantee and an ephemeral URL), sustained public traffic, anything where the origin is a laptop that closes at midnight, or compliance-sensitive data that must not transit a personal-origin machine.

---

## 4. Teardown

`cloud/teardown.md` — codespace stop/delete, ephemeral tunnel (nothing to clean),
local container cleanup; the GHCR package is intentionally kept public as the
Task 1 deliverable.
