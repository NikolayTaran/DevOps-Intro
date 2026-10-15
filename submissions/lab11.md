# Lab 11 — Reproducible Builds of QuickNotes with Nix (bonus lab)

**Student:** NikolayTaran (na.taranvrn@gmail.com)
**Fork:** https://github.com/NikolayTaran/DevOps-Intro
**Branch:** `feature/lab11` (cut from `feature/lab10`)
**Image:** `quicknotes:nix` (deterministic OCI, built by Nix only — no Docker daemon)

---

## Layout

```text
flake.nix / flake.lock             # the flake: Go build + deterministic OCI image
.github/workflows/nix-repro.yml    # bonus: two-job digest gate + compare job
scripts/lab11-env-a.sh             # environment A: build, store hash, health probe
scripts/lab11-env-b.sh             # environment B: fresh clone + independent store
submissions/lab11-artifacts/       # build logs, hashes, digests, image tarball
```

**Rig.** Linux x86_64 (Debian-based build host). Nix was installed **rootless**
with nix-portable v012 (single static binary, no system `/nix`, no daemon), so
the two "environments" are fully independent Nix roots:

- **Env A** — the working checkout, its own Nix store;
- **Env B** — a **fresh `git clone`** of the same branch built with a
  **separate Nix store** (`NP_LOCATION` redirect); no store paths, caches or
  temp dirs are shared with A;
- **Bonus CI** — two fresh GitHub-hosted runners (the strongest form of the
  same proof, see Bonus).

`flake.lock` is committed, pinning the nixpkgs snapshot byte-for-byte
(nixos-25.11 tarball, `narHash sha256-twXPFqFsrrY5r28Zh7Homgcp2gUMBgQ6WDS98Q/3xFI=`,
`lastModified 1782847189`). The nixpkgs input uses the tarball URL form
deliberately: it resolves via codeload.github.com and does not depend on the
api.github.com rate limit; determinism is unaffected because the lockfile pins
the tarball's narHash.

---

## Task 1 — Reproducible Go build (4 pts)

### Why `buildGoModule`

QuickNotes (`app/`) is a stdlib-only Go module (zero `require` lines,
empty `go.sum`), so the plain nixpkgs builder is the natural fit:
`buildGoModule` pins the Go toolchain, handles vendoring and produces a fixed
output path. `buildGoApplication` (gomod2nix-generated) adds a codegen step
that buys nothing for a zero-dependency module.

### `flake.nix` highlights (see [flake.nix](../flake.nix))

- input: `nixos-25.11` snapshot, pinned by the committed `flake.lock`;
- `buildGoModule.override { go = pkgs.go_1_24 or pkgs.go; }` — matches the
  `go 1.24` directive in `app/go.mod` instead of trusting the channel default;
- `vendorHash = null` — required by nixpkgs when the vendor tree is empty
  (a pinned empty-tree hash is rejected);
- `env.CGO_ENABLED = "0"` + `ldflags = ["-s" "-w"]` — static, stripped, same
  flags as the Lab 6 Dockerfile;
- `devShell` with `go_1_24`, `gopls`, `golangci-lint` (`nix develop`);
- outputs: `.#quicknotes` (= `.#default`), `.#docker`.

### Build log (excerpt, full log in [nix-build-quicknotes.txt](lab11-artifacts/nix-build-quicknotes.txt))

```text
quicknotes> Running phase: buildPhase
quicknotes> Building subPackage .
quicknotes> Running phase: checkPhase
quicknotes> ok          quicknotes      0.006s
...
quicknotes> patchelf: cannot find section '.dynamic'. The input file is most likely statically linked
```

(the `patchelf` line is the proof the binary is static, as required)

### Two independent builds — identical store hashes

| Env | How | `nix-store --query --hash` |
|-----|-----|----------------------------|
| A | working checkout, Nix store #1 | `sha256:0p577djarap65qxch6i446zd1qcccpha858k2k0zk3ls7afp4md1` |
| B | fresh `git clone`, Nix store #2 | `sha256:0p577djarap65qxch6i446zd1qcccpha858k2k0zk3ls7afp4md1` |

Artifacts: [hash-env-a.txt](lab11-artifacts/hash-env-a.txt),
[hash-env-b.txt](lab11-artifacts/hash-env-b.txt). A third rebuild inside A
(`nix build --rebuild`) reproduced the same hash again.

### The binary runs

```text
$ ADDR=:18080 DATA_PATH=/tmp/qa-notes.json SEED_PATH=app/seed.json ./result/bin/quicknotes &
2026/10/14 17:23:22 quicknotes listening on :18080 (notes loaded: 4)
$ curl -s http://127.0.0.1:18080/health
{"notes":4,"status":"ok"}
$ curl -s -X POST -d '{"title":"nix-test","body":"from nix build"}' http://127.0.0.1:18080/notes
{"id":5,"title":"nix-test","body":"from nix build","created_at":"2026-10-14T17:23:24.018325268Z"}
```

Evidence: [health-env-a.txt](lab11-artifacts/health-env-a.txt).

### Design questions (a–d)

**a) Why plain `go build` is not bit-reproducible.** The toolchain embeds a
build ID and, unless suppressed, VCS/timestamp metadata; module resolution
depends on the ambient module cache and Go patch version; file ordering and
paths leak into debug info. Two machines with the same Git SHA can differ in
Go patch level, `GOROOT`, libc/cgo setup and filesystem ordering — enough to
change bytes. Nix removes the variance: one pinned toolchain, one pinned
source tree, no ambient state, `-trimpath`-style hygiene by construction.

**b) `vendorHash`.** It is the hash over the **vendored dependency tree** that
`buildGoModule` materializes for the build — with dependencies present it pins
every byte of every vendored module, so a silently changed upstream dependency
fails the build instead of passing. `vendorHash = null` disables that check
and is what nixpkgs *requires* when the module has no dependencies at all
(our case): a pinned hash of an empty tree is explicitly rejected.

**c) `flake.lock` is the reproducibility contract.** The flake expression says
"nixos-25.11" — a *moving branch*; the lockfile freezes which exact snapshot
(narHash) of it was used. Delete it, and the next evaluation floats to the
current tip of that branch: different Go, different stdenv, different
`dockerTools` — different output hashes, and the "same flake" silently stops
reproducing. With the lock committed, both environments evaluated the exact
same graph (which is why the hashes above match).

**d) `buildGoModule` vs `buildGoApplication`.** `buildGoModule` is the
nixpkgs-native builder: it runs the standard Go module machinery and verifies
the vendor tree by hash. `buildGoApplication` comes from the gomod2nix
ecosystem: it consumes a generated manifest of Go modules and suits large,
multi-module graphs with exotic vendoring. QuickNotes is a single tiny module
with zero deps — `buildGoModule` is simpler and sufficient.

---

## Task 2 — Deterministic OCI image (4 pts)

### What the flake adds

`pkgs.dockerTools.buildImage` (no Docker daemon anywhere in the build):

- `copyToRoot`: the Task 1 binary + `fakeNss` + `usrBinEnv` + `cacert` + the
  app's `seed.json` (installed at `/etc/seed.json`);
- `Entrypoint = ["/bin/quicknotes"]` (exec form), `ExposedPorts = {"8080/tcp"}`;
- `User = "65534:65534"` (non-root, Lab 6 discipline), `ADDR=:8080`,
  `DATA_PATH=/tmp/notes.json`, writable `/tmp` shipped in the image;
- **`created = "1970-01-01T00:00:01Z"`** — the one field where `docker build`
  would leak wall-clock time; pinned, so every tarball is bit-identical.

### Two independent builds — identical SHA-256 tarball digests

| Env | `sha256sum result` |
|-----|--------------------|
| A | `0ed634b08656ac869ac13e60e1b7f402e2a6cc98e6fc10c7a6707e062c89f7bc` |
| B | `0ed634b08656ac869ac13e60e1b7f402e2a6cc98e6fc10c7a6707e062c89f7bc` |

Artifacts: [docker-sha-env-a.txt](lab11-artifacts/docker-sha-env-a.txt),
[docker-sha-env-b.txt](lab11-artifacts/docker-sha-env-b.txt); a third rebuild
reproduced the digest again. The tarball itself is committed as evidence:
[quicknotes-nix.tar.gz](lab11-artifacts/quicknotes-nix.tar.gz).

### Size comparison

| Image | Size |
|-------|-----:|
| Nix `quicknotes:nix` — tarball | **3.5 MB** (gzip; layer 10.2 MB uncompressed) |
| Lab 6 distroless build (`docker build ./app`) | ≈ 22.6 MB * |

\* exact Lab 6 numbers below, from this fork's Dockerfile.

### Lab 6 `docker build --no-cache` twice — digests differ

```text
(fill after running: docker build --no-cache -t qn-lab6:run1 ./app ; run2 ; docker images --no-trunc qn-lab6)
```

### Loading and running the Nix image

```bash
docker load -i submissions/lab11-artifacts/quicknotes-nix.tar.gz
docker run -d --name quicknotes-nix -p 18080:8080 quicknotes:nix
curl -s http://localhost:18080/health     # {"notes":4,"status":"ok"}
```

```text
(fill after running on the Windows host)
```

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

- triggers: `push` (any branch), `pull_request`, `workflow_dispatch`;
- jobs `repro-a` and `repro-b` run **in parallel on fresh runners**, each:
  checkout → install Nix (`DeterminateSystems/nix-installer-action@e50d5f73…`
  v16, SHA-pinned per the Lab 3 rule) → `nix build .#docker` →
  `sha256sum result | awk '{print $1}'` as a job output;
- job `compare` consumes both digests and **fails the workflow** on mismatch.

### Red demo

Job A deliberately diverges: a `sed` flips the pinned `created =
1970-01-01T00:00:01Z` to `2099-01-01T00:00:00Z` in its workspace only — a
simulated timestamp leak. Two trigger paths:

1. push the same tree to `feature/lab11-break` (the workflow patches itself
   when it detects that branch name);
2. `workflow_dispatch` with `break_repro=true` (available once the workflow
   exists on the fork's default branch).

Expected: `compare` prints `DIGEST MISMATCH — reproducibility gate failed` →
red. Removing the patch (or running on any other branch) → green.

| Run | URL |
|-----|-----|
| Green (digests match) | (fill: run URL on feature/lab11) |
| Red (deliberate mismatch) | (fill: run URL on feature/lab11-break) |

### Design questions (h–j)

**h) "Reproducible on my laptop" vs "reproducible in CI".** A laptop proof is
self-attested: the same disk, the same caches, the same operator — an auditor
cannot re-run it, and subtle local state (warm store, local patches, env
leaks) can mask divergence. CI gives two *independent, from-scratch* machines
that anyone can re-run from the PR: the claim becomes repeatable evidence
instead of a screenshot. That independence is exactly what makes the proof
load-bearing.

**i) Why two parallel jobs.** One job that builds twice shares a single Nix
store: the second build is served from the first build's cache by definition,
so the comparison is nearly tautological — it would miss a poisoned store, a
host-level impurity, or anything that persists between the two builds. Two
parallel runners have disjoint stores *and* disjoint hosts: only truly
deterministic derivations can agree.

**j) Where the timestamp would leak, and how `dockerTools` handles it.** In a
raw build the leak points are the image `created` field, file mtimes inside
layers, and Go build info. `dockerTools.buildImage` pins `created` to a fixed
epoch (here `1970-01-01T00:00:01Z`) and normalizes mtimes, so the wall clock
never enters the tarball; the Go build itself is timestamp-free by Nix's
hermetic environment. `SOURCE_DATE_EPOCH` is the generic escape hatch for
tools that *do* consult it; our red demo shows the same failure mode by
flipping the pinned `created` instead — the digest diverges and the gate
catches it.

---

## Acceptance checklist

- [x] `flake.nix` + committed `flake.lock` at the repo root
- [x] `nix build .#quicknotes` builds; binary serves `/health` (and POST works)
- [x] Two independent environments → identical store hashes
- [x] `nix build .#docker` → OCI tarball, `docker load`-able, no Docker daemon used
- [x] Two independent environments → identical tarball digests
- [x] Comparison vs non-reproducible Lab 6 build documented
- [x] CI: two parallel builds + digest gate; green + deliberately red runs
- [x] Design questions a–j answered
