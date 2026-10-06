# Lab 9 — DevSecOps: Trivy + ZAP + govulncheck

QuickNotes (Go notes API) scanned with **Trivy 0.59.1** (image / fs / config / CycloneDX SBOM),
**OWASP ZAP 2.16.0 baseline** (passive only), plus a **`govulncheck` PR-blocking gate** added to the
Lab 3 CI workflow. Every HIGH/CRITICAL finding is dispositioned below; one class of findings is
fixed in code (security-headers middleware), and the govulncheck gate is demonstrated catching a
deliberately introduced vulnerable dependency (red → revert → green).

- **Course PR:** inno-devops-labs/DevOps-Intro#1733 (`feature/lab9` → `main`)
- **Demo PR (CI runs):** NikolayTaran/DevOps-Intro#3 — the course repo's Actions do not execute
  for fork PRs (every student PR shows "Workflow runs completed with no jobs"), so the CI gate is
  demonstrated on the same workflow / same commits in the fork.
- **Artifacts:** [`submissions/lab9-artifacts/`](lab9-artifacts/) — raw scan outputs, ZAP before/after
  reports, ZAP run config, CycloneDX SBOM.

---

## Task 1 — Trivy: image / fs / config / SBOM (6 pts)

### 1.1 Scans run

Trivy is pinned to `aquasec/trivy:0.59.1` (never `:latest`). Vuln scans use `--severity HIGH,CRITICAL`.

| # | Scan | Command (abbreviated) | Raw output |
|---|------|----------------------|------------|
| 1 | Image (first pass, before fixes) | `docker run --rm aquasec/trivy:0.59.1 image --severity HIGH,CRITICAL quicknotes:lab6` | [trivy-image.txt](lab9-artifacts/trivy-image.txt) |
| 2 | Image (after builder bump + demo pin) | same, re-run against the rebuilt image | [trivy-image-after.txt](lab9-artifacts/trivy-image-after.txt) |
| 3 | Image (final, after revert) | same, re-run against the final rebuilt image | [trivy-image-final.txt](lab9-artifacts/trivy-image-final.txt) |
| 4 | Filesystem (repo) | `docker run --rm -v %cd%:/ws aquasec/trivy:0.59.1 fs --severity HIGH,CRITICAL /ws` | [trivy-fs.txt](lab9-artifacts/trivy-fs.txt) |
| 5 | Config / misconfig | `docker run --rm -v %cd%:/ws aquasec/trivy:0.59.1 config /ws` | [trivy-config.txt](lab9-artifacts/trivy-config.txt) |
| 6 | SBOM (CycloneDX 1.6) | `docker run --rm aquasec/trivy:0.59.1 image --format cyclonedx quicknotes:lab6` | [sbom-quicknotes.cdx.json](lab9-artifacts/sbom-quicknotes.cdx.json) |

### 1.2 Triage — every HIGH/CRITICAL dispositioned

#### A. Image scan, first pass (`trivy-image.txt`)

OS layer (debian 12.15): **0 HIGH / 0 CRITICAL** — nothing to triage.
Go binary (`gobinary`): **19 HIGH**, all in the Go **standard library v1.24.13** that the builder
image `golang:1.24-alpine` baked into the binary:

| # | CVE (stdlib v1.24.13) | Area | Fixed in | Disposition |
|---|----------------------|------|----------|-------------|
| 1 | CVE-2026-25679 | net/url | 1.25.8 / 1.26.1 | **FIX** |
| 2 | CVE-2026-27145 | crypto/x509 | 1.25.11 / 1.26.4 | **FIX** |
| 3 | CVE-2026-32280 | crypto/x509, crypto/tls | 1.25.9 / 1.26.2 | **FIX** |
| 4 | CVE-2026-32281 | crypto/x509 | — (1.26.x) | **FIX** |
| 5 | CVE-2026-32283 | crypto/tls | — (1.26.x) | **FIX** |
| 6 | CVE-2026-33811 | net | 1.25.10 / 1.26.3 | **FIX** |
| 7 | CVE-2026-33814 | net/http/internal/http2 | 1.26.x | **FIX** |
| 8 | CVE-2026-33818 | encoding/asn1 | 1.25.13 / 1.26.6 | **FIX** |
| 9 | CVE-2026-39820 | net/mail | 1.25.10 / 1.26.3 | **FIX** |
| 10 | CVE-2026-39821 | net/http, x/net/idna | 1.25.13 / 1.26.6 | **FIX** |
| 11 | CVE-2026-39822 | os.Root | 1.25.12 / 1.26.5 | **FIX** |
| 12 | CVE-2026-39836 | net | 1.25.10 / 1.26.3 | **FIX** |
| 13 | CVE-2026-42499 | net/mail | — (1.26.x) | **FIX** |
| 14 | CVE-2026-42504 | mime | 1.25.11 / 1.26.4 | **FIX** |
| 15 | CVE-2026-56853 | net/http | 1.25.13 / 1.26.6 | **FIX** |
| 16 | CVE-2026-56858 | html/template | — (1.26.x) | **FIX** |
| 17 | CVE-2026-56859 | encoding/xml | — (1.26.x) | **FIX** |
| 18 | CVE-2026-56860 | net/url | — (1.26.x) | **FIX** |
| 19 | CVE-2026-56862 | crypto/tls | — (1.26.x) | **FIX** |

**FIX (all 19):** bump the builder stage `golang:1.24-alpine` → `golang:1.26-alpine` in
`app/Dockerfile` (commit `c90b6adf4d` — same commit that lands the Task 2 middleware, so the
rebuilt image ships both a patched stdlib and the security headers). The re-scan confirms it: the
`stdlib` section is gone entirely in `trivy-image-after.txt`. Since every finding was fixed with a
one-line base-image bump, none required per-CVE ACCEPT paperwork.

#### B. Image re-scan + filesystem scan (`trivy-image-after.txt`, `trivy-fs.txt`)

The rebuild for the Bonus CI demo happened while the **temporary** demo dependency
`golang.org/x/net v0.30.0` was pinned (commit `bebfec045b`, `app/vuln-demo.go` — see Bonus
section). Both scans then report the same **6 HIGH**, all in `golang.org/x/net`:

| # | CVE | Component | Fixed in | Disposition | Evidence |
|---|-----|-----------|----------|-------------|----------|
| 1 | CVE-2024-45338 | x/net/html | 0.33.0 | **FIX** — demo dep reverted | commit `7d0451f63a` |
| 2 | CVE-2026-25681 | x/net/html | 0.55.0 | **FIX** — demo dep reverted | commit `7d0451f63a` |
| 3 | CVE-2026-27136 | x/net/html | none released yet | **WATCH** — see note | — |
| 4 | CVE-2026-33814 | x/net (http2) | 0.53.0 | **FIX** — demo dep reverted | commit `7d0451f63a` |
| 5 | CVE-2026-39821 | x/net/idna | 0.55.0 | **FIX** — demo dep reverted | commit `7d0451f63a` |
| 6 | CVE-2026-46600 | x/net/dns/dnsmessage | 0.56.0 | **FIX** — demo dep reverted | commit `7d0451f63a` |

- **FIX ×5:** the dependency existed only for the bonus demo (a temporary `countLinks` helper that
  parses HTML). The revert commit `7d0451f63a` removes the demo files and drops the module via
  `go mod tidy` — the findings disappear from both the module graph and the rebuilt image.
- **WATCH (CVE-2026-27136):** no fixed upstream version exists yet, so there is nothing to bump
  *to*. The practical exposure was already eliminated by removing the module itself. Watch item:
  re-check the x/net release notes if/when the module is ever re-introduced. Re-evaluation date:
  **2026-12-06** (≤ 6 months).

#### C. Secrets check inside the fs scan (`trivy-fs.txt`)

| Finding | Severity | Disposition |
|---------|----------|-------------|
| `.vagrant/machines/default/virtualbox/private_key` — Asymmetric Private Key | HIGH | **FALSE POSITIVE** |

Reason: Vagrant auto-generates this per-machine SSH key as *local machine state* for the Lab 5 VM.
It is not version-controlled — the file does not exist anywhere in the pushed tree (verified against
the branch), so no secret ships in the repository. Trivy `fs` simply walked the local working
directory where Vagrant keeps it.

#### D. Config scan (`trivy-config.txt`)

28 misconfig checks across Dockerfile/compose: **0 HIGH / 0 CRITICAL**. One LOW
(AVD-DS-0026 — "Add HEALTHCHECK instruction"): below this lab's severity bar; noted as a future
hardening item, since the app already exposes `/health` for the compose stack to probe.

#### E. Post-fix verification (final image)

`trivy image --severity HIGH,CRITICAL quicknotes:lab6` on the final image (demo dep reverted,
builder on 1.26): **0 HIGH / 0 CRITICAL** — [trivy-image-final.txt](lab9-artifacts/trivy-image-final.txt).

### 1.3 CycloneDX SBOM

Generated from the image with Trivy 0.59.1, spec CycloneDX 1.6 — full file:
[sbom-quicknotes.cdx.json](lab9-artifacts/sbom-quicknotes.cdx.json). First 30 lines:

```json
{
  "$schema": "http://cyclonedx.org/schema/bom-1.6.schema.json",
  "bomFormat": "CycloneDX",
  "specVersion": "1.6",
  "serialNumber": "urn:uuid:268e38e9-5452-411b-a460-ec62a1d6583d",
  "version": 1,
  "metadata": {
    "timestamp": "2026-10-06T14:53:00+00:00",
    "tools": {
      "components": [
        {
          "type": "application",
          "group": "aquasecurity",
          "name": "trivy",
          "version": "0.59.1"
        }
      ]
    },
    "component": {
      "bom-ref": "pkg:oci/quicknotes@sha256%3Aaadafe1c69709673a015d9bae5847dc3adf3c6489ef348ff48923db2097fb313?arch=amd64&repository_url=index.docker.io%2Flibrary%2Fquicknotes",
      "type": "container",
      "name": "quicknotes:lab6",
      "purl": "pkg:oci/quicknotes@sha256%3Aaadafe1c69709673a015d9bae5847dc3adf3c6489ef348ff48923db2097fb313?arch=amd64&repository_url=index.docker.io%2Flibrary%2Fquicknotes",
      "properties": [
        {
          "name": "aquasecurity:trivy:DiffID",
          "value": "sha256:114dde0fefebbca13165d0da9c500a66190e497a82a53dcaabc3172d630be1e9"
        },
        {
          "name": "aquasecurity:trivy:DiffID",
          "value": "sha256:35b5ba6e08cdd034b8d1920f9c7203e5d66f258e1915f164a01de0af14f34710"
        },
```

The SBOM enumerates every component of `quicknotes:lab6` (OS packages + Go modules) with purl
identifiers and exact versions, signed by the image digest — a machine-readable inventory of what
actually ships.

### 1.4 Design questions

**a) Severity is one input, not the answer.** What else matters when triaging?
- *Reachability* — is the vulnerable function actually called? (This lab: 19 stdlib CVEs vs. 6
  module CVEs that govulncheck proved reachable — see Bonus. Trivy flags module presence;
  govulncheck proves call-graph reachability.)
- *Exploit availability* — is there a public exploit / is it in CISA KEV?
- *Deployment context* — internet-facing vs internal, auth in front, data sensitivity, blast radius.
- *Fix cost & compensating controls* — a one-line base-image bump (here) vs. a breaking major
  upgrade; WAF/rate-limiting as temporary mitigation.
- *Exposure of the vulnerable path* — a CVE in `crypto/x509` chain building matters more for a
  TLS server than for a CLI tool that never parses untrusted certs.

**b) Why is the minimal base the strongest single security control?**
The debian 12.15 layer produced **0 HIGH/CRITICAL** while the same image carried 19 HIGH findings
in the Go binary itself. A minimal/distroless base removes the shell, package manager and the
entire apt package set — i.e. it deletes whole *classes* of findings before any scanner runs. Fewer
components = fewer CVEs to triage forever, smaller patch surface, and nothing for an attacker to
pivot through (no shell, no curl) in case of RCE.

**c) When is `.trivyignore` the right move, and when is it security theater?**
Right: a documented, dated, owner-attributed acceptance for a *specific* finding (false positive
with reasoning, or ACCEPT with a re-evaluation date), reviewed in the PR like any code change.
Theater: a dumping ground — suppressing findings silently to get a green pipeline, without
disposition/owner/date, or ignoring whole scanners/dirs. The ignore-file must stay as auditable as
the findings it hides; otherwise it just moves the risk out of sight.

**d) What concrete future problem does the SBOM solve today?**
Log4Shell-style response: the day CVE-20XX-XXXX drops for component Y, you answer "are we
affected?" in minutes by grepping a machine-readable inventory (purls + versions + image digests)
instead of rebuilding and re-scanning every artifact. It also gives you an audit trail per release
and a diffable component manifest between image versions.

---

## Task 2 — OWASP ZAP baseline + fix in code (4 pts)

### 2.1 Baseline run

- Pinned image `ghcr.io/zaproxy/zaproxy:2.16.0`, run via `zap-baseline.py` — **passive scan only,
  no active scan** — against the running Lab 6 stack, target `http://host.docker.internal:8080`.
- Reports: [zap-before.html](lab9-artifacts/zap-before.html) /
  [zap-before.json](lab9-artifacts/zap-before.json); run config auto-generated by the script:
  [zap.yaml](lab9-artifacts/zap.yaml).

### 2.2 Triage — every finding (before)

| ID | Alert | Risk | Affected URL(s) | Disposition |
|----|-------|------|-----------------|-------------|
| 10021 | X-Content-Type-Options Header Missing | Low | GET `/health` | **FIX** — middleware (below) |
| 90004 | Insufficient Site Isolation Against Spectre Vulnerability (no `Cross-Origin-Resource-Policy`) | Low | GET `/health` | **FIX** — middleware (below) |
| 10049 | Storable and Cacheable Content | Informational | `/`, `/health`, `/robots.txt`, `/sitemap.xml` (4 instances) | **FIX (mitigate)** — `Cache-Control: no-store` |
| 10116 | ZAP is Out of Date | Low | `/` — the *scanner itself* (pinned 2.16.0 vs latest 2.17.0) | **ACCEPT** — scanner noise, not an app property; version is pinned deliberately for reproducible scans. Re-evaluate: **2026-12-06** (bump the ZAP tag next lab cycle) |

### 2.3 The fix — middleware, all routes, guarded by tests (commit `c90b6adf4d`)

- **`app/security.go`** — `securityHeaders` middleware setting six headers on *every* response:
  `Content-Security-Policy: default-src 'none'`, `X-Content-Type-Options: nosniff`,
  `X-Frame-Options: DENY`, `Cross-Origin-Resource-Policy: same-origin`,
  `Cache-Control: no-store`, `Referrer-Policy: no-referrer`.
- **Wired at the router edge** in `main.go` (`Handler: securityHeaders(server.Routes())`) — applies
  to all routes and even mux-generated 404s, not just `/health` (requirement 2.3.1–2.3.2).
- **`app/security_test.go`** — asserts all six headers on `GET /health`, `GET /metrics`,
  `GET /notes`, `POST /notes`, `GET/DELETE /notes/999` **and** on the mux 404 `/no-such-route`
  (requirement 2.3.3). The test calls `securityHeaders(...)` directly, so deleting the middleware
  breaks the build — the fix is genuinely guarded, not a comment (requirement 2.3.4).

### 2.4 Re-scan — the findings are gone

After rebuilding the image and re-running the same baseline:
[zap-after.html](lab9-artifacts/zap-after.html) / [zap-after.json](lab9-artifacts/zap-after.json).

| ID | Before | After |
|----|--------|-------|
| 10021 X-Content-Type-Options Missing | Low, 1 instance | **gone** |
| 90004 Spectre Site Isolation | Low, 1 instance | **gone** |
| 10049 | "Storable and Cacheable Content" (4 instances) | now "Non-Storable Content", informational, **evidence: `no-store`** — ZAP literally observes the new header; confirms the mitigation instead of flagging a gap |
| 10116 ZAP Out of Date | Low | unchanged (accepted scanner noise) |

Net effect: every application-level WARN from the baseline is eliminated; passive rules passing
went from 63 to 65.

### 2.5 Design questions

**e) Why a middleware and not per-handler header sets?**
One enforcement point at the router edge cannot drift: new handlers get the headers for free,
error paths and mux-404s (which no one "remembers" to touch) are covered, and there is exactly one
place to unit-test. Per-handler `Header().Set` calls guarantee omissions — one new endpoint or one
error branch and the protection silently disappears.

**f) `Content-Security-Policy: default-src 'none'` — what does it break, and why is it OK here?**
It blocks every subresource and inline execution: scripts, styles, images, fonts, fetch/XHR, frames.
Any site serving HTML/JS/CSS breaks immediately. QuickNotes is a JSON API that serves no browser
assets — there is nothing to break, and as a bonus, if someone ever *does* accidentally render
attacker-controlled HTML, the strict CSP keeps injected scripts dead. A real website would need an
allowlist (`script-src 'self'`, etc.) instead of the nuclear default.

**g) What's the cost of marking informational findings "accepted" without reading them?**
Alert fatigue. Blanket-accepting noise trains the team to ignore ZAP output entirely — and the day
a real Medium-severity finding hides between twelve accepted noise rows, it ships to production
behind a "green" report. Informational does not mean worthless: 10049 was informational, and acting
on it (no-store) still removed a real cache-leak class. Every finding gets read and dispositioned;
"accept" is a decision, not a default.

---

## Bonus — govulncheck as a CI PR gate (2 pts)

### B.1–B.2 Implementation (`.github/workflows/ci.yml`, commit `6aa6260bda`)

- New **`govulncheck`** job: `working-directory: app`, installs
  `golang.org/x/vuln/cmd/govulncheck@v1.1.4` (**pinned**, never `@latest`), runs `govulncheck ./...`.
- Toolchain: vet/test/govulncheck run on Go **1.26** — the same toolchain the Dockerfile builds
  with (`go.mod` language version stays 1.24). The lint job pins Go 1.24 because golangci-lint
  v2.5.0 is built with Go 1.25 and panics type-checking a 1.26 toolchain — documented inline in the
  workflow.
- Aggregate **`ci-ok`** job (`needs: [vet, test, lint, govulncheck]`, `if: always()`) fails the PR
  when any gate fails — the check that "blocks the PR" (requirement B.2.4).
- Lab 3 discipline kept: runner pinned `ubuntu-24.04`, every third-party action pinned to a full
  commit SHA, least-privilege `permissions: contents: read`.

### B.2.5 Demonstration — the gate catches a bad dependency

Demo PR: NikolayTaran/DevOps-Intro#3 (same workflow, same commits; the course repo's Actions do
not run for fork PRs).

1. **Introduce:** temporary pin `golang.org/x/net v0.30.0` (commit `bebfec045b`) with
   `app/vuln-demo.go` calling `html.Parse`; commit `6fc5831114` makes the call reachable from an
   `init()` entry point.
2. **RED:** [run 37496080060](https://github.com/NikolayTaran/DevOps-Intro/actions/runs/37496080060)
   — `govulncheck` fails with **exit code 3**, reporting symbol-level findings
   (GO-2026-5030, GO-2026-5029, GO-2026-5028, …) each traced as
   `quicknotes.countLinks calls html.Parse` at `vuln-demo.go:16:27`; `ci-ok` fails; vet/test/lint
   stay green. Screenshot: ![red run](screenshots/lab9-1.png)
3. **Revert:** commit `7d0451f63a` removes the demo files and drops the dependency (`go mod tidy`).
4. **GREEN:** [run 37496505239](https://github.com/NikolayTaran/DevOps-Intro/actions/runs/37496505239)
   — all five jobs pass, `ci-ok` 2s. Screenshot: ![green run](screenshots/lab9-2.png)

### B.3 Design questions

**h) How is "module has a CVE but we don't call the affected function" different — and what does
that mean for triage workload?**
govulncheck's call-graph analysis separates *imported* from *reachable*: a vulnerability whose
affected symbols are never called is reported as informational and does not fail the gate; a
reachable one fails the PR. Triage workload collapses from "disposition every CVE in every
transitive module" (Trivy's module-level view) to "disposition only the handful the scanner proves
runnable from our code" — the analysis runs automatically on every PR instead of by hand.

**i) Why pin the scanner version, not just `@latest`?**
A gate must mean the same thing every run: with `@latest`, a tool update can silently change
findings and turn green pipelines red (or hide regressions) with no code change — a gate that
moves under you trains the team to ignore it. Pinning gives a controlled upgrade path (read the
release notes, re-triage, bump deliberately) and supply-chain hygiene: the scanner is third-party
code you execute against your source on every commit.

**j) What does govulncheck NOT catch that Trivy's image scan would?**
govulncheck only sees Go modules in the build graph. It is blind to: OS packages in the base image
(debian layer), non-Go binaries and static assets, Dockerfile/compose misconfigurations, embedded
secrets, and anything in the runtime image that did not come from `go.mod`. That is exactly
Trivy's breadth (image/fs/config/secrets). The two are complementary: Trivy = artifact-level
coverage, govulncheck = Go call-graph depth — which is why this repo ships both.

---

## Result summary

| Task | Points | Status |
|------|-------:|--------|
| Trivy image/fs/config/SBOM + per-finding triage | 6 | 19 stdlib HIGH **FIX**ed (builder bump), 5 x/net HIGH **FIX**ed (revert), 1 **WATCH**, 1 secret **FALSE POSITIVE**; final image 0 HIGH/CRITICAL |
| ZAP baseline + fix in code + re-scan | 4 | 10021 + 90004 eliminated, 10049 mitigated (`no-store`), 10116 accepted; fix = middleware on all routes + guarded tests |
| govulncheck PR gate | +2 | Pinned v1.1.4 in CI behind `ci-ok`; red run caught the demo dep (`countLinks calls html.Parse`), revert → green |
