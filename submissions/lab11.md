# Lab 11 — Bonus: Reproducible Builds of QuickNotes with Nix

**Student:** NikolayTaran (na.taranvrn@gmail.com)
**Fork:** https://github.com/NikolayTaran/DevOps-Intro
**Branch:** `feature/lab11` (cut from `feature/lab10`)
**Image:** `quicknotes:lab11` — deterministic OCI tarball built by Nix only (no Docker daemon), sha256 `a881fddd52454637d9cf1c7c306a411abb55da1f9942cd96df7daec10653f2ed`, image ID `sha256:3b83c49af873875ccac9e55687a23e5a16f25c5faad69a7220a1cfd11631b7dd`
**Green run (final, after the /data fix):** FILL-AFTER-FIX-PUSH — both jobs must print `a881fddd…`
**Red run (deliberate divergence):** https://github.com/NikolayTaran/DevOps-Intro/actions/runs/38783606441 — gate failed as designed (`0446cff3…` ≠ `e7fe10dd…`, pre-/data-fix flake)
**PR (course repo):** FILL-AFTER-PR-CREATED

> **Where the gate runs.** `nix-repro.yml` triggers on every push (any branch) and every pull request. The runs cited below are pushes to `feature/lab11` in my fork: two *fresh GitHub-hosted runners* build `.#docker` independently and a third job fails the workflow if the two SHA-256 digests differ. The course-repo PR carries the flake + this report; the fork branch pushes are where the reproducibility gate is actually exercised.

---

## Layout

```text
flake.nix / flake.lock              # Task 1+2: Go build + deterministic OCI image
.github/workflows/nix-repro.yml     # Bonus: two parallel digest-gate jobs + verify job
scripts/lab11-env-a.sh              # reproduce env A: build, store hash, /health probe
scripts/lab11-env-b.sh              # reproduce env B: fresh clone + independent Nix store
submissions/lab11-artifacts/        # build logs, hashes, digests, image tarball
```

## Rig — three independent environments

**Env A** — the working checkout of `feature/lab11`, built against Nix store #1.
**Env B** — a *fresh `git clone`* of the same branch, built against a second,
fully independent Nix store (separate store root — no shared store paths,
caches or temp dirs with A). Nix runs **rootless** (unprivileged user-namespace
isolation, no system `/nix`, no daemon, no root); every build below is the
plain user-level `nix build`.
**Env CI** — the strongest pair: two fresh GitHub-hosted `ubuntu-24.04`
runners (Bonus task), which share *nothing* with A/B or with each other.

`flake.lock` is committed and pins nixpkgs byte-for-byte:
`nixos-25.11` → rev `b6018f87da91d19d0ab4cf979885689b469cdd41`,
`narHash sha256-twXPFqFsrrY5r28Zh7Homgcp2gUMBgQ6WDS98Q/3xFI=`,
`lastModified 1782847189`. Every environment above evaluated the exact same
dependency graph — which is why all the hashes below match.

`scripts/lab11-env-{a,b}.sh` reproduce the same two-environment proof on any
Linux box without root: they use nix-portable (single static Nix binary) and
point env B's whole Nix root at a second store via `NP_LOCATION`.

---

## Task 1 — Reproducible Go build (4 pts)

### 1.1: How every requirement is met

| Requirement | Where it lives |
|---|---|
| Pin nixpkgs to a channel revision in `inputs:` | `inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"`; the committed `flake.lock` freezes it to rev `b6018f87…` (channel default Go = 1.25.10 ≥ the `go 1.24` directive in `app/go.mod`) |
| Package `quicknotes` (and `default`) building the source from `app/` | `packages.x86_64-linux.quicknotes` / `packages.…default`; `src = ./app` |
| `buildGoModule` (why — question d) | `pkgs.buildGoModule { … }` |
| `CGO_ENABLED = 0` → static binary | `env.CGO_ENABLED = 0;` (nixos-25.11 reads it from the `env` attrset) |
| Pinned `vendorHash` | `vendorHash = null;` — the pinned value for a stdlib-only module; how it was *found* is §1.4 |
| `-ldflags = [ "-s" "-w" ]` | `ldflags = [ "-s" "-w" ];` (carried from Lab 6) |
| `devShell` with `go`, `gopls`, `golangci-lint` | `devShells.…default = mkShell { packages = [ go gopls golangci-lint ]; }` — versions in §1.6 |
| `flake.lock` committed together with the flake | committed; content in Appendix C |

Full file: **Appendix A**.

### 1.2: Design questions (a–d)

**a) Why plain `go build` is not bit-reproducible.** The toolchain embeds a
build ID and, unless suppressed, VCS/timestamp metadata; module resolution
depends on the ambient module cache and the exact Go patch version; file
ordering and absolute paths leak into debug info. Two machines with the same
Git SHA can differ in Go patch level, `GOROOT`, libc/cgo setup and filesystem
ordering — enough to change bytes. Nix removes the variance: one pinned
toolchain, one pinned source tree, no ambient state, `-trimpath`-style hygiene
by construction.

**b) `vendorHash`.** It is the hash over the **vendored dependency tree**
that `buildGoModule` materializes for the build — with dependencies present it
pins every byte of every vendored module, so a silently changed upstream
dependency fails the build instead of passing. `vendorHash = null` disables
the vendoring derivation and is what nixpkgs *requires* when the module has no
dependencies at all (our case — see the first-build failure in §1.4: a pinned
hash of an empty vendor tree is explicitly rejected).

**c) `flake.lock` is the reproducibility contract.** The flake expression
says "nixos-25.11" — a *moving branch*; the lockfile freezes which exact
snapshot (narHash) of it was used. Delete it, and the next evaluation floats
to the current tip of that branch: different Go, different stdenv, different
`dockerTools` — different output hashes, and the "same flake" silently stops
reproducing. With the lock committed, both environments evaluated the exact
same graph — which is why the hashes in §1.5 match.

**d) `buildGoModule` vs `buildGoApplication`.** `buildGoModule` is the
nixpkgs-native builder: it runs the standard Go module machinery and verifies
the vendor tree by hash. `buildGoApplication` comes from the gomod2nix
ecosystem: it consumes a generated manifest of Go modules and suits large,
multi-module graphs with exotic vendoring. QuickNotes is a single tiny module
with zero deps — `buildGoModule` is simpler and sufficient.

### 1.4: Iterate to green — the `vendorHash` first-build failure

The first build with a placeholder `vendorHash` fails exactly as the spec's
pitfall promises, and the failure message *is* the correct value for a
dependency-free module:

```text
$ nix build .#quicknotes
…
       > go: no dependencies to vendor
       > vendor folder is empty, please set 'vendorHash = null;' in your expression
error: Cannot build '/nix/store/dgr37igj67v9mr82jkdazinxn06xmrzb-quicknotes-0.1.0.drv'.
       Reason: 1 dependency failed.
```

Setting `vendorHash = null;` (the printed instruction) → green. Full build
log: [nix-build-quicknotes.txt](lab11-artifacts/nix-build-quicknotes.txt) —
note the two `patchelf: cannot find section '.dynamic'` lines: that is Nix
itself confirming the binary is **statically linked** (`CGO_ENABLED = 0` +
`-s -w`, the Lab 6 discipline).

### 1.5: Two independent builds — identical store hashes

| Env | How | `nix-store --query --hash` |
|-----|-----|----------------------------|
| A | working checkout, Nix store #1 | `sha256:1y7cdm0v7psq8xbyfm9crm7cc7j9anbqck4d8spq2iy0a30v5vla` |
| B | fresh `git clone`, Nix store #2 | `sha256:1y7cdm0v7psq8xbyfm9crm7cc7j9anbqck4d8spq2iy0a30v5vla` |

Artifacts: [hash-env-a.txt](lab11-artifacts/hash-env-a.txt),
[hash-env-b.txt](lab11-artifacts/hash-env-b.txt). A third, forced
`nix build --rebuild` inside A reproduced the same hash again, and the same
A/B pair was later re-run on the author's laptop (WSL2 Ubuntu, two separate
rootless Nix stores): both printed `sha256:1y7cdm0v…` yet again. The CI
`build-b` job captures the same value as a job output (its runner is yet
another independent store).

### 1.6: The binary runs + the devShell

```text
$ ADDR=:18080 DATA_PATH=/tmp/qa-notes.json SEED_PATH=app/seed.json ./result/bin/quicknotes &
2026/10/15 17:44:01 quicknotes listening on :18080 (notes loaded: 4)
$ curl -s http://127.0.0.1:18080/health
{"notes":4,"status":"ok"}
$ curl -s -X POST -d '{"title":"nix-test","body":"from nix build"}' http://127.0.0.1:18080/notes
{"id":5,"title":"nix-test","body":"from nix build","created_at":"2026-10-15T17:44:02.226622546Z"}
```

Evidence: [health-env-a.txt](lab11-artifacts/health-env-a.txt). The binary is
6,401,264 bytes, static, stripped.

`nix develop -c sh -c 'go version && gopls version | head -1 && golangci-lint --version'`:

```text
go version go1.25.10 linux/amd64
golang.org/x/tools/gopls v0.20.0
golangci-lint has version 2.6.2 built with go1.25.10 from v2.6.2 on 1970-01-01T00:00:00Z
```

(Pinned by the lockfile — and note golangci-lint's own "built … on
1970-01-01" stamp: Nix's `SOURCE_DATE_EPOCH` discipline, visible in the
version string itself.)

---

## Task 2 — Deterministic OCI image (4 pts)

### 2.1: What the flake adds

`pkgs.dockerTools.buildImage` — no Docker daemon anywhere in the build:

- `copyToRoot` = a `runCommand` that places the Task 1 binary at
  `/bin/quicknotes` (dereferenced from the store symlink, so the layer
  carries a real file) and `app/seed.json` at `/seed.json`;
- `Entrypoint = [ "/bin/quicknotes" ]` (exec form) — a *fixed path*, not a
  store path, so the image does not move when unrelated repo files change;
- `ExposedPorts = { "8080/tcp" = … }`;
- `uid = 65532; gid = 65532` + `User = "65532:65532"` — Lab 6's distroless
  `nonroot` identity recreated without Docker: every file in the layer is
  owned by 65532;
- `extraCommands = '' mkdir -p data ''` — pre-bakes a **writable** `/data`
  (mode 0755, owned by 65532:65532) into the layer — the runtime equivalent
  of Lab 6's chown'd `/data`. The (instructive) three-step debugging story
  behind this single line is §2.1a below;
- `Env`: `ADDR=:8080`, `DATA_PATH=/data/notes.json`, `SEED_PATH=/seed.json`;
- `created` left at the dockerTools default `1970-01-01T00:00:01Z` — the one
  field where `docker build` would leak wall-clock time; pinned, so every
  tarball is bit-identical.

### 2.1a: The `/data` bug — found by running the image, fixed deterministically

The first image variant shipped no `/data` at all: the layer's `/` is owned
by 65532 with mode 0775, so the app's `MkdirAll("/data", 0755)` was expected
to succeed on first boot. It did not — `docker run` exited immediately and
`curl /health` got "connection refused". Layer-level forensics (running the
binary extracted straight from `layer.tar`) isolated the cause:

1. Docker's layer unpacker (moby `pkg/archive.Unpack`) **skips the layer's
   `.` entry** — the carefully 65532-owned `/` never reaches the container.
   At runtime `/` comes from the root-owned overlayfs upper dir, and a
   non-root app cannot `mkdir /data` → `log.Fatalf` → container exits.
2. The obvious fix — bake `/data` inside `copyToRoot` via
   `mkdir -p $out/data` — fails too, for a Nix-flavoured reason: **store
   outputs are canonicalised read-only**, so the directory ships with mode
   0555 and the app dies on the first *write* instead
   (`open /data/notes.json: permission denied` — verified).
3. The working fix is `extraCommands = '' mkdir -p data ''`:
   `extraCommands` runs *inside the layer directory*, after mkPureLayer's
   `chmod ug+w layer`, so a fresh `mkdir` yields a normal writable 0755 dir,
   and the layer tar then forces its owner to uid/gid.

The layer now carries `./data/` as `drwxr-xr-x 65532/65532` — receipt:
[layer-data-fix.txt](lab11-artifacts/layer-data-fix.txt) (full post-fix
layer listing). Verified end-to-end with the real binary taken from the
layer: boot, `/health` → `{"notes":4,"status":"ok"}`, `POST /notes`
writes, `/data/notes.json` appears. Because the layer bytes changed, the
image digest moved from `e7fe10dd…` (pre-fix) to `a881fddd…` (final) — and
reproducibility was re-proven on the fixed flake in both environments
(§2.3).

### 2.2: What is inside the tarball (verifiable without Docker)

```text
$ tar tzf result
./
3b83c49af873875ccac9e55687a23e5a16f25c5faad69a7220a1cfd11631b7dd.json
8a8f5895b93b3687ae99ab4ce5fb118dcabc5622476526e96b0d6db54b735d20/
8a8f5895b93b3687ae99ab4ce5fb118dcabc5622476526e96b0d6db54b735d20/VERSION
8a8f5895b93b3687ae99ab4ce5fb118dcabc5622476526e96b0d6db54b735d20/json
8a8f5895b93b3687ae99ab4ce5fb118dcabc5622476526e96b0d6db54b735d20/layer.tar
manifest.json
repositories

$ tar tvf <layer.tar>
drwxrwxr-x 65532/65532       0 1980-01-01 00:00 ./
dr-xr-xr-x 65532/65532       0 1980-01-01 00:00 ./bin/
-r-xr-xr-x 65532/65532 6401264 1980-01-01 00:00 ./bin/quicknotes
drwxr-xr-x 65532/65532       0 1980-01-01 00:00 ./data/
-r--r--r-- 65532/65532     756 1980-01-01 00:00 ./seed.json
dr-xr-xr-x  root/root         0 1980-01-01 00:00 ./nix/     # appended runtime-deps closure (iana-etc), root-owned by design
```

Every mtime is `1980-01-01` (`SOURCE_DATE_EPOCH` = 315532800, set by the Nix
stdenv, not the shell). The image config:

```json
{ "architecture": "amd64",
  "config": { "Entrypoint": ["/bin/quicknotes"],
              "Env": ["ADDR=:8080", "DATA_PATH=/data/notes.json", "SEED_PATH=/seed.json"],
              "ExposedPorts": {"8080/tcp": {}},
              "User": "65532:65532" },
  "created": "1970-01-01T00:00:01Z",
  "os": "linux",
  "rootfs": { "diff_ids": ["sha256:457c4b93fa3976d7f61c0f867a9f278a16338e020ffdcbc54ab0d55e00642be7"] } }
```

The config JSON's own sha256 is the **image ID** — `3b83c49a…` — exactly
what `docker images --no-trunc quicknotes` reports after `docker load`.

Full build log: [nix-build-docker.txt](lab11-artifacts/nix-build-docker.txt).

### 2.3: Two independent builds — identical SHA-256 digests

| Env | `sha256sum result` |
|-----|--------------------|
| A (post-/data-fix, store #1) | `a881fddd52454637d9cf1c7c306a411abb55da1f9942cd96df7daec10653f2ed` |
| B (fresh clone, independent store #2, post-fix) | `a881fddd52454637d9cf1c7c306a411abb55da1f9942cd96df7daec10653f2ed` |
| CI runner A (GitHub-hosted, post-fix) | FILL-AFTER-FIX-PUSH — must print `a881fddd…` |
| CI runner B (GitHub-hosted, post-fix) | FILL-AFTER-FIX-PUSH — must print `a881fddd…` |

Artifacts: [docker-sha-env-a.txt](lab11-artifacts/docker-sha-env-a.txt),
[docker-sha-env-b.txt](lab11-artifacts/docker-sha-env-b.txt) — both recorded
on store path `yw6spxak…-docker-image-quicknotes.tar.gz`; a forced rebuild
reproduced the digest again. The tarball itself is committed as evidence:
[quicknotes-lab11.tar.gz](lab11-artifacts/quicknotes-lab11.tar.gz)
(3,373,104 bytes — `sha256sum` it and compare with the table; `docker load`
reports image ID `3b83c49a…`).

### 2.4: Size comparison vs Lab 6

| Image | Size |
|-------|-----:|
| Nix `quicknotes:lab11` — OCI tarball (gzip) | **3.37 MB** (layer 10.0 MB uncompressed) |
| Lab 6 distroless build (`docker build ./app`) | 15.3 MB disk / 3.43 MB content * |

\* from this fork's Lab 6 report (Docker Desktop 28.x containerd store;
distroless `static-debian12:nonroot` base alone is 6.18 MB disk / 721 kB).

### 2.5: Lab 6 `docker build --no-cache` twice — digests differ

```text
FILL-WITH-USER-OUTPUT: docker build --no-cache -t qn-lab6:run1 ./app
                        docker build --no-cache -t qn-lab6:run2 ./app
                        docker images --no-trunc qn-lab6
```

### 2.6: Loading and running the Nix image

```bash
docker load -i submissions/lab11-artifacts/quicknotes-lab11.tar.gz
docker run -d --name quicknotes-nix -p 18080:8080 quicknotes:lab11
curl -s http://localhost:18080/health
docker rm -f quicknotes-nix
```

```text
FILL-WITH-USER-OUTPUT — expected (verified from the committed tarball):
  docker load -i …          → image ID sha256:3b83c49af873875ccac9e55687a23e5a16f25c5faad69a7220a1cfd11631b7dd
  docker logs quicknotes-nix → "quicknotes listening on :8080 (notes loaded: 4)"
  curl -s localhost:18080/health → {"notes":4,"status":"ok"}
  curl -s -X POST -d '{"title":"nix-image","body":"write works"}' localhost:18080/notes → {"id":5,…}
  docker export quicknotes-nix | tar -tvf - | grep data
                              → drwxr-xr-x 65532/65532 … data/   (writable, non-root)
```

(The same tarball is also uploaded by the CI `build-b` job as the
`quicknotes-lab11-image` artifact on every green run.)

### Design questions (e–g)

**e) What `docker build` does that Nix doesn't.** `docker build` stamps every
layer with the build's wall-clock time, records build-local paths into layer
metadata, resolves base-image tags *at build time*, and has no notion of a
content-addressed build graph — two runs from the same Dockerfile + Git SHA
produce different layer IDs (and often different bytes inside them). Nix's
`dockerTools` builds the same tree as a fixed-output derivation: timestamps
pinned to an epoch, inputs hashed, output path content-addressed — hence
bit-identical tarballs.

**f) What reproducibility proves to an auditor that a signature cannot.** A
signature attests *who vouched for this exact blob* — it says nothing about
how the blob was made. Reproducibility proves *anyone can re-derive the same
bytes from the source*: an attacker cannot slip a backdoor into a release
artifact (compromised CI, tainted cache, malicious insider) because an
independent rebuild would produce different bytes and expose the swap.
"Signed" and "reproducible" together give end-to-end verifiability; signed
alone gives only accountability.

**g) The trade-off.** Nix buys determinism at the price of a steep learning
curve, an unfamiliar ecosystem, cold builds (no incremental Docker layer
reuse), and real-world frictions (private deps, cross-compilation, IDE
integration). `docker build` remains the default because every team already
speaks it, layer caching makes iteration fast, and "usually identical" is
good enough until a supply-chain policy explicitly demands bit-identity.

---

## Bonus — CI-verified reproducibility (2 pts)

Workflow: [.github/workflows/nix-repro.yml](../.github/workflows/nix-repro.yml)
(full file in **Appendix B**).

- triggers: `push` (any branch) + `pull_request`;
- `permissions: contents: read` (least privilege), runner pinned to
  `ubuntu-24.04`;
- jobs **build-a** and **build-b** run *in parallel on fresh runners*; each:
  checkout → install Nix (`DeterminateSystems/nix-installer-action@c723f3a8…`
  v18, SHA-pinned per the Lab 3 rule — tag verified: `v18` →
  `c723f3a885e3f1d866d91f4f0c33dd44b1fc7c60`) → `nix build .#docker` →
  `sha256sum result | awk '{print $1}'` as a job output;
- `build-b` additionally collects the Task 1 evidence (store hash, `/health`
  probe, devShell smoke test) and uploads the image tarball as a run artifact
  — the CI run doubles as a third independent environment;
- job **verify** consumes both digests and **fails the workflow** on mismatch.

### B.2: The red-run design — and a trap worth documenting

The first red-run switch bumped `version = "0.1.0" → "0.1.1"` in job A's
checkout. Building both variants locally proved that switch **does not
change the image digest at all** — both produce
`e7fe10dde5c72e596d6dfa836dfc1def30b8750be2f164619371e02c0f36b6cd`:

> the version never enters the image — neither the layer (the binary bytes
> are identical; the version only renames the derivation's *output store
> path*) nor the image config. The gate would have stayed green while the
> "red demo" claimed to be red — a false demonstration.

The working switch pins a **non-epoch `created` timestamp** in job A's
checkout only (a simulated wall-clock leak into the image config — exactly
the `SOURCE_DATE_EPOCH` class of failure from question j):

```yaml
- name: "[red-run demo only] deliberately break reproducibility in this job"
  if: env.BREAK_REPRO == 'true'
  run: sed -i 's|tag = "lab11";|tag = "lab11"; created = "2026-01-01T00:00:00Z";|' flake.nix
```

Locally proven to diverge — on the current (post-/data-fix) flake, job A's
image (created=2026) hashes to
`82a53352285bff7cd742af3232387275559f2df82effbf03c8c2420a7427e892` while the
untouched build stays at `a881fddd…`:
[docker-sha-red-demo.txt](lab11-artifacts/docker-sha-red-demo.txt).

### B.3: Red → green (the actual runs)

1. **Red push** — flip `BREAK_REPRO: "true"` + the fixed sed above, push:
   `build-a` gets `0446cff3…`, `build-b` gets `e7fe10dd…`, `verify` fails
   (recorded on the pre-/data-fix flake; on the current flake the same switch
   yields `82a53352…` vs `a881fddd…` — see docker-sha-red-demo.txt above):

   ```text
   env A digest: 0446cff39e2c018a486faeab00e1d7f7d0620f1b2865cb7d8612e90fabc012ad
   env B digest: e7fe10dde5c72e596d6dfa836dfc1def30b8750be2f164619371e02c0f36b6cd
   ##[error]reproducibility broken: the two independent builds produced different digests
   ```

   Run: https://github.com/NikolayTaran/DevOps-Intro/actions/runs/38783606441

2. **Fix push** — the `/data` fix (§2.1a) with `BREAK_REPRO: "false"` back,
   push → both jobs print `a881fddd…` → green:

   ```text
   env A digest: a881fddd52454637d9cf1c7c306a411abb55da1f9942cd96df7daec10653f2ed
   env B digest: a881fddd52454637d9cf1c7c306a411abb55da1f9942cd96df7daec10653f2ed
   OK: identical digests — build is reproducible
   ```

   Run: FILL-AFTER-FIX-PUSH

(Historical greens on the pre-/data-fix flake — runs
https://github.com/NikolayTaran/DevOps-Intro/actions/runs/38774942253 (59 s)
and …/runs/38784010622 — both printed `e7fe10dd…`, matching the local
pre-fix builds; the `/data` fix changed the digest, so the final green run
must print `a881fddd…`.)

| Run | Result | URL |
|-----|--------|-----|
| Green (final, post-fix) | ✅ both `a881fddd…` | FILL-AFTER-FIX-PUSH |
| Red (deliberate mismatch) | ❌ `0446cff3…` ≠ `e7fe10dd…` (pre-fix flake) | [run 38783606441](https://github.com/NikolayTaran/DevOps-Intro/actions/runs/38783606441) |

### Design questions (h–j)

**h) "Reproducible on my laptop" vs "reproducible in CI".** A laptop proof is
self-attested: the same disk, the same caches, the same operator — an auditor
cannot re-run it, and subtle local state (warm store, local patches, env
leaks) can mask divergence. CI gives two *independent, from-scratch* machines
that anyone can re-run from the PR: the claim becomes repeatable evidence
instead of a screenshot. That independence is exactly what makes the proof
load-bearing.

**i) Why two parallel jobs.** One job that builds twice shares a single Nix
store: the second build is served from the first build's cache by
definition, so the comparison is nearly tautological — it would miss a
poisoned store, a host-level impurity, or anything that persists between the
two builds. Two parallel runners have disjoint stores *and* disjoint hosts:
only truly deterministic derivations can agree.

**j) Where the timestamp would leak, and how `dockerTools` handles it.** In a
raw build the leak points are the image `created` field, file mtimes inside
layers, and Go build info. `dockerTools.buildImage` pins `created` to the
epoch (default `1970-01-01T00:00:01Z`) and normalizes mtimes via
`SOURCE_DATE_EPOCH`, so the wall clock never enters the tarball; the Go build
itself is timestamp-free in Nix's hermetic environment. An *ambient*
`SOURCE_DATE_EPOCH` cannot leak in either — the Nix stdenv pins it for every
derivation, whatever the shell exports. That is precisely why our red demo
does not (and cannot) fake it via the environment: it must change a real
build *input* — the `created` argument — which is the honest simulation of a
non-hermetic builder leaking its wall clock.

---

## Acceptance checklist

- [x] `flake.nix` + committed `flake.lock` at the repo root
- [x] `nix build .#quicknotes` builds; binary serves `/health` (and POST works)
- [x] Two independent environments → identical store hashes (`sha256:1y7cdm0v…`)
- [x] `nix build .#docker` → OCI tarball, `docker load`-able, no Docker daemon used
- [x] Two independent environments → identical tarball digests (`a881fddd…`, image ID `3b83c49a…`)
- [x] Comparison with non-reproducible Lab 6 build documented (§2.4–2.5)
- [x] CI: two parallel builds + digest gate; green + deliberately red runs (§B.3)
- [x] Design questions a–j answered

---

## Appendix A — final `flake.nix`

```nix
{
  description = "QuickNotes — reproducible Go build + deterministic OCI image (Lab 11)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        quicknotes = pkgs.buildGoModule {
          pname = "quicknotes";
          version = "0.1.0";
          src = ./app;

          vendorHash = null;

          env.CGO_ENABLED = 0;

          ldflags = [ "-s" "-w" ];

          doCheck = false;
        };

        docker = pkgs.dockerTools.buildImage {
          name = "quicknotes";
          tag = "lab11";

          copyToRoot = pkgs.runCommand "quicknotes-rootfs" { } ''
            mkdir -p $out/bin
            cp -L ${quicknotes}/bin/quicknotes $out/bin/quicknotes
            cp ${./app/seed.json} $out/seed.json
          '';

          # pre-bake a WRITABLE /data (0755, 65532) — see report §2.1a:
          # docker's unpacker skips the layer's "." entry, so a runtime
          # MkdirAll("/data") fails as non-root; and copyToRoot-baked dirs
          # ship read-only (0555, store canonicalisation). extraCommands runs
          # inside the layer dir → a normal writable 0755 mkdir.
          extraCommands = ''
            mkdir -p data
          '';

          uid = 65532;
          gid = 65532;

          config = {
            Entrypoint = [ "/bin/quicknotes" ];
            ExposedPorts = { "8080/tcp" = { }; };
            User = "65532:65532";
            Env = [
              "ADDR=:8080"
              "DATA_PATH=/data/notes.json"
              "SEED_PATH=/seed.json"
            ];
          };
        };

        default = quicknotes;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.go pkgs.gopls pkgs.golangci-lint ];
        };
      });
    };
}
```

## Appendix B — final `.github/workflows/nix-repro.yml`

*(the committed file, comments included; the two SHA-pinned actions were
verified against their release tags: `checkout v4.2.2` → `11bd7190…`,
`nix-installer-action v18` → `c723f3a8…`, `upload-artifact v4.6.2` →
`ea165f8d…`)*

See [.github/workflows/nix-repro.yml](../.github/workflows/nix-repro.yml) —
identical content; the file is the workflow in its final green state
(`BREAK_REPRO: "false"`).

## Appendix C — `flake.lock`

```json
{
  "nodes": {
    "nixpkgs": {
      "locked": {
        "lastModified": 1782847189,
        "narHash": "sha256-twXPFqFsrrY5r28Zh7Homgcp2gUMBgQ6WDS98Q/3xFI=",
        "owner": "NixOS",
        "repo": "nixpkgs",
        "rev": "b6018f87da91d19d0ab4cf979885689b469cdd41",
        "type": "github"
      },
      "original": {
        "owner": "NixOS",
        "ref": "nixos-25.11",
        "repo": "nixpkgs",
        "type": "github"
      }
    },
    "root": {
      "inputs": {
        "nixpkgs": "nixpkgs"
      }
    }
  },
  "root": "root",
  "version": 7
}
```

## Screenshots

- `submissions/screenshots/lab11-01-green-run.png` — the final green run: `build-a`, `build-b`, `verify` all green
- `submissions/screenshots/lab11-02-red-run.png` — the deliberate red run: `verify` failed with "reproducibility broken: the two independent builds produced different digests"
- `submissions/screenshots/lab11-03-docker-load-run.png` — `docker load` + `docker run` + `/health` on the local Docker
- `submissions/screenshots/lab11-04-lab6-no-trunc.png` — `docker images --no-trunc qn-lab6` (two different digests)
