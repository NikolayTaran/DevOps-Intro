# Lab 3 — CI/CD: A PR-Gated Pipeline for QuickNotes

**Student:** NikolayTaran (na.taranvrn@gmail.com)
**Fork:** https://github.com/NikolayTaran/DevOps-Intro
**Branch:** `feature/lab3`
**Path chosen: GitHub Actions**
**Green run:** https://github.com/NikolayTaran/DevOps-Intro/actions/runs/35165902196
**PR (course repo):** https://github.com/inno-devops-labs/DevOps-Intro/pull/1574 — *(fill in the course-repo PR number right after you open it, then commit "docs(lab3): add PR link" and push)*
**PR (my fork — where the gate actually runs):** https://github.com/NikolayTaran/DevOps-Intro/pull/1

**Chosen path: GitHub Actions.** I can sign in to github.com, my fork already lives there with SSH signing set up in Lab 1, and my fork's `main` already carries an active ruleset from the Lab 1 bonus — the natural place to bolt a PR gate onto. The internal GitLab (`gitlab.pg.innopolis.university`) remains a fallback for access problems, not the default.

> **Where the gate runs.** Workflows defined in `feature/lab3` execute for pull requests **inside my fork** (`feature/lab3` → my fork's `main`); for the course-repo PR GitHub runs the course repo's own workflows, not mine. So the fork PR is the playground where the gate is proven (green runs, the deliberate red run, branch protection), and the course-repo PR above delivers the config + this report.

---

## Task 1 — Write the PR Gate (6 pts)

### 1.1: How every requirement is met

| Requirement | Where it lives |
|---|---|
| Trigger: push to `main` + every PR targeting `main` | `on: push` (`branches: [main]`) + `on: pull_request` (`branches: [main]`) |
| **vet** → `go vet ./...` against `app/` | job `vet`, `defaults.run.working-directory: app` |
| **test** → `go test -race -count=1 ./...` against `app/` | job `test` |
| **lint** → `golangci-lint run` against `app/`, **v2.5.0 pinned** | job `lint`, `version: v2.5.0` |
| Pinned runtime (no `ubuntu-latest`) | `runs-on: ubuntu-24.04` everywhere |
| All third-party (and first-party) actions pinned by full 40-char SHA with tag comment | `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2`, `actions/setup-go@d35c59abb061a4a6fb18e82ac0862c26744d6ab5 # v5.5.0`, `golangci/golangci-lint-action@4afd733a84b1f43292c61721a86cd11f3bb1338122a9 # v8.0.0` |
| `permissions:` least privilege | `permissions: contents: read` at workflow level |
| PR **fails** if any unit fails | three independent jobs; branch protection (1.6) requires the `ci-ok` aggregate (Task 2) to be green before merging |

The full final workflow file is in **Appendix A**. Evolution: v1 = the three jobs only (baseline for timings) → v2 added the cache → v3 added matrix + `ci-ok` + path filter → final version added the bonus optimizations.

### 1.2: Design questions

**a) Why pin the runner version (`ubuntu-24.04`) instead of `ubuntu-latest`?**
`ubuntu-latest` is a *moving pointer*: GitHub migrates it to newer runner images over time (24.04 → 26.04 …), and every migration changes what is preinstalled — Go builds, Docker versions, available libraries. A pipeline that was green on Monday turns red (or, worse, silently behaves differently) on Thursday with **zero changes in my repo**, and nobody can reproduce the failure because the environment no longer exists. Pinning `ubuntu-24.04` freezes the environment definition; the only things that can change my CI's behavior are my own commits and explicit upstream updates of the two SHA-pinned actions. That is the difference between "it works" and "it is reproducible".

**b) Why split vet + test + lint into separate jobs? What would happen with one combined job?**
Three wins: (1) **parallelism** — GitHub spins up a runner per job, so wall-clock is `max(vet, test, lint)` instead of the sum; (2) **granular status** — the PR immediately shows *which* unit failed (`test` red, `vet` green), not an opaque "CI failed", and I can re-run only the failed job; (3) **independent environments** — lint gets its own pinned golangci-lint install and cannot contaminate or be contamined by the test job's build cache, and each unit is an independently required check, so the gate is exact. One combined job would run them sequentially (~sum of times), report a single red status that hides the cause, force full re-runs on any failure, and make "require the lint check" impossible — you'd require the blob.

**c) What real attack does SHA pinning prevent? Cite the date + name of the incident from Lecture 3.**
Tag hijacking. A mutable tag (`v4`) can be moved by a compromised maintainer or an attacker with push access to point at a *different* commit than the one you reviewed — and every workflow referencing the tag silently starts executing the attacker's code with the runner's token and secrets. Commit SHAs are immutable: the same 40 hex chars always mean the same tree. The incident: **tj-actions/changed-files supply-chain attack, March 14, 2025** — the attacker rewrote *all* version tags of the action to a malicious commit that dumped runner memory (secrets included) into build logs; thousands of repositories executed the payload automatically because they referenced the tags, not SHAs.

**d) What is `permissions:` and what's the principle behind it?**
It declares the access scope of the automatically-issued `GITHUB_TOKEN` for the workflow (or a single job). The principle is **least privilege**: the token should be able to do only what the job actually needs — here, reading the repository (`contents: read`) — and nothing else. Without an explicit restriction the token inherits the repository defaults, which may include write access to contents or pull requests; a compromised step (say, a hijacked action from question *c*) would then be able to push code, open PRs, or edit releases. With `contents: read` the blast radius of that same compromise shrinks to "can read public code that is public anyway".

**e) GitLab path (not my path, answered for completeness): what's the difference between a *stage* and a *job*? What would `dependencies:` do that `stages:` doesn't?**
A **stage** is a phase of the pipeline — a grouping/sequencing level; all jobs of stage B start only after every job of stage A succeeds. A **job** is the concrete unit of work: its own image, script, variables, rules. `stages:` control only *when* things run; they say nothing about *data flow*. `dependencies:` is the artifact-level link: it declares which earlier jobs' artifacts a job downloads (and can even bend the linear order — a job in a later stage can pull artifacts from two stages back and skip intermediate ones). In GitHub Actions terms: stage ≈ the implicit ordering via `needs`, job ≈ job, `dependencies:` ≈ `actions/upload-artifact`/`download-artifact` wiring.

### 1.4: Iterate to green

The baseline workflow (three jobs, single Go 1.24) passed on the first PR run — the two traps I pre-empted: Go commands must run in `app/` (`defaults.run.working-directory`, otherwise "no Go files" from the repo root), and `golangci-lint` must be pinned to `v2.5.0` because the repo's `app/.golangci.yml` uses the v2 config format.

### 1.5: Prove the gate works

Deliberate breakage — `app/handlers_test.go`, the health-check assertion, expected count `1` changed to `2`:

```
$ git commit -S -s -am "test(lab3): deliberately break health count check"
[feature/lab3 5570bb9] test(lab3): deliberately break health count check
 1 file changed, 1 insertion(+), 1 deletion(-)

$ git push
To https://github.com/NikolayTaran/DevOps-Intro
   cb04f6e..5570bb9  feature/lab3 -> feature/lab3
```

Result: the `test` job goes red —

```
--- FAIL: TestHealth_ReportsCount (0.00s)
    handlers_test.go:53: notes count: 1
FAIL
FAIL    quicknotes
```

— and the PR shows **Merging is blocked**: required status checks have not passed. Screenshot: `submissions/screenshots/lab3-02-red-blocked.png` (red `test` check + the blocked-merge banner).

The fix — a follow-up commit restoring the expected value:

```
$ git commit -S -s -am "test(lab3): restore expected notes count"
[feature/lab3 6edb363] test(lab3): restore expected notes count
 1 file changed, 1 insertion(+), 1 deletion(-)

$ git push
To https://github.com/NikolayTaran/DevOps-Intro
   5570bb9..6edb363  feature/lab3 -> feature/lab3
```

Everything green again, merge allowed. Screenshot: `submissions/screenshots/lab3-01-green-run.png`.

### 1.6: Branch protection

My fork already had the `main-protection` ruleset from the Lab 1 bonus (require PR, signed commits, linear history). I extended it with the CI requirements: **Require status checks to pass before merging** (the required check is `ci-ok` — see Task 2.2 for why one aggregate instead of `vet`/`test`/`lint`) and **Require branches to be up to date before merging**. Screenshot: `submissions/screenshots/lab3-03-branch-protection.png` (Settings → Rules → Rulesets → `main-protection`, the status-checks rule visible).

---

## Task 2 — Make It Fast and Smart (4 pts)

### 2.1: Cache the dependency download

`actions/setup-go` with `cache: true` caches both the Go module cache and the build cache. One QuickNotes-specific twist: the module has **zero dependencies** (`app/go.mod` has no `require` block, and `app/go.sum` does not exist), and `setup-go` *fails hard* when it cannot find the dependency file it is supposed to hash ("Dependencies file is not found"). So the cache key is anchored to `app/go.mod` instead:

- `cache-dependency-path: app/go.mod` — the file exists, and its hash is exactly the "inputs changed?" signal (a module with zero deps changes inputs only when the Go version directive changes).
- The generated key is `setup-go-<os>-<arch>-<imageOS>go-<version>-<hash>`: the **Go version is part of the key**, so the 1.23 and 1.24 matrix cells never fight over the same cache entry.
- First run on a key = miss + save; subsequent runs restore. The **module** cache is empty (nothing to download — that's the "boring" row the spec predicted); the **build** cache is what actually persists (`go vet` / `go test` compilation outputs), which shows up in the per-step timings below rather than in the job total.

### 2.2: Matrix build

`vet` and `test` now run as a `strategy.matrix` over Go `1.23` and `1.24`, `fail-fast: false` so a failure in one cell doesn't cancel the other — the whole point is *seeing which combo broke*. Two things had to change in the repo for the matrix to be honest:

1. `app/go.mod` declared `go 1.24`, which makes a 1.23 toolchain refuse to run ("go.mod requires go >= 1.24"). I lowered the directive to `go 1.23` — the minimum supported version — in commit `chore(app): lower go directive to 1.23 for the CI matrix`. Both toolchains build the same source; the directive now states the floor instead of the ceiling.
2. `env: GOTOOLCHAIN: local` — without it, a 1.23 runner silently *downloads and switches to* 1.24 on seeing the old directive (the default `GOTOOLCHAIN=auto`), which would make the "1.23" cell a fake green that never tested 1.23. `local` pins the cell to exactly the toolchain `setup-go` installed.

The matrix renames the checks (`test (1.23)`, `test (1.24)`, …), which would leave any protection rule requiring the old names stuck on "Expected — Waiting for status". I used the robust fix from the spec: a single aggregation job `ci-ok` (`if: always()`, `needs: [vet, test, lint]`, fails if any need failed or was cancelled) — branch protection requires **only `ci-ok`**, so the matrix can change freely.

### 2.3: Skip docs-only changes

Both triggers now carry `paths: ['app/**', '.github/workflows/ci.yml', 'submissions/**']`. README edits don't match → the workflow doesn't even start → no CI minutes burned. I included `submissions/**` deliberately: report-only commits then still produce a fresh `ci-ok` on the PR head (keeping the fork PR mergeable); a root-`README.md` edit still skips — demonstrated below.

**Demonstration:** PR #2 (fork, `docs-skip-demo` → `main`, only touches root `README.md`) — the Actions tab shows **zero workflow runs** for it, and the PR's check area stays empty ("Expected — waiting" forever, which is the documented trade-off of path filters + required checks for *pure-docs* PRs). Screenshot: `submissions/screenshots/lab3-04-docs-skip.png`.

### 2.4: Timing table

Median of 3 measured runs per scenario (Re-run all jobs on the same commit; runners vary, so single numbers lie):

| Scenario | Wall-clock (median of 3) |
|----------|--------------------------|
| Baseline (no cache, single Go 1.24, no path filter) | 34 s |
| With cache | 31 s |
| With cache + matrix | 37 s |

**Reading of the table.** As the spec predicted, the cache rows are boring — and that is the finding: with zero third-party dependencies there is no module download to skip, so `cache: true` can only shave the build-cache seconds inside `go vet`/`go test` (`setup-go` itself: ~11 s → ~2 s on a warm cache; `go test` compile+run: ~20 s → as low as 1 s when the build cache hits). The dominant costs are runner provisioning, checkout, the Go toolchain download, and the golangci-lint binary install — none of which the module cache touches. A dependency-heavy project would see the module-download step (tens of seconds to minutes) collapse to a cache restore; here the honest answer is "the cache is insurance that costs ~2 s and pays out nothing yet". The matrix row doesn't grow wall-clock because cells run in parallel — it buys coverage, not speed.

### Design questions

**f) Why cache `go.sum`-keyed inputs and not build outputs?**
Inputs pinned by `go.sum` are *deterministic*: the same hash list always resolves to bit-identical modules, so a cache entry keyed by that hash is valid forever and safe to reuse blindly — it's a content-addressed contract, the same idea as Git objects. Build outputs are *not* deterministic across contexts: they depend on toolchain version, build flags, GOOS/GOARCH, and ambient state, so a restored "output" may be subtly stale or wrong for the current configuration — worst case the pipeline uses artifacts that don't correspond to the source it claims to test, and the failure looks like flaky tests, not like caching. (Nuance worth stating: `setup-go` does also restore the Go *build* cache, which is keyed per toolchain — that's safe for exactly the same reason: the key includes the version, and build-cache misses merely recompile.)

**g) What does `fail-fast: false` change, and when do you actually want `fail-fast: true`?**
`false` means a failing cell does not cancel its siblings: all four matrix combinations run to completion, so the PR shows the *complete map* of which toolchains are broken — that's the diagnostic value of the matrix. `true` (the GitHub default) aborts the rest on first failure: use it when the remaining cells are pointless after the first red — e.g. very expensive suites where cancelled runs save real money, one fix is going to address all cells anyway, or downstream jobs would burn resources on data from a run that's already known-bad.

**h) What's the risk of an attacker writing a cache that protected branches later read?**
Cache poisoning: a malicious PR runs a workflow that *saves* a cache entry (e.g. tampered "dependencies" or compiled objects), and a later run on a protected branch restores that entry — building production artifacts from attacker-controlled bytes. GitHub's mitigations (official docs: *Security hardening for GitHub Actions* + *Caching dependencies → "Restrictions for accessing a cache"*): caches are scoped to the repository and keyed by branch — a workflow run can restore caches from its own branch and the base branch's default scope, but **pull requests from forks cannot write to the base repository's cache scope at all** (they get a fork-scoped, read-against-base arrangement, and their save is silently skipped), and the `GITHUB_TOKEN` in fork PRs is read-only. On top of that my key is a `go.mod`/`go.sum` hash, so a poisoned entry under a stolen key would still have to hash-match the real inputs. The residual risk is same-repo attackers with branch access — which your threat model treats as trusted anyway.

---

## Bonus — Pipeline Performance Investigation (2 pts)

### B.1: Profile (final pipeline, per-step, from the CI UI)

| Unit | Step | Time |
|------|------|------|
| any job | runner start / job setup | 0–2 s |
| any job | `actions/checkout` | 0–1 s |
| vet / test | `actions/setup-go` (toolchain download) | 1–10 s (9–10 s on a cold key, 1–2 s warm) |
| vet | actual `go vet ./...` | 4–11 s (4 s on 1.24 warm, 11 s on 1.23 cold-ish) |
| test | actual `go test -race -count=1 ./...` | 1–20 s (1 s on 1.23 warm, 20 s on 1.24 first compile) |
| lint | golangci-lint binary install (first run) → cached restore (later runs) | ~22 s → ~16 s |
| lint | actual `golangci-lint run` | inside the 16 s action step (download/restore + run) |
| ci-ok | the one shell command | 2 s (whole job) |

### B.2: Optimizations applied beyond Task 2 (three)

1. **golangci-lint binary cache** — removed `skip-cache: true` from the lint job: the action's built-in caching stores the ~30 MB pinned `v2.5.0` binary after the first run and restores it in ~1–2 s afterwards, instead of downloading and verifying it every run ("avoid `go install` on every run" from the spec's list).
2. **`GOFLAGS: -buildvcs=false`** — disables VCS stamping (`*.ok`/build-id embedding of git state) for every `go build`/`go test` invocation: CI never needs the version stamp, and the flag removes git-dependency from compilation paths (also the documented workaround for detached/limited-history checkouts).
3. **`concurrency: ci-<workflow>-<ref>` with `cancel-in-progress: true`** — when I push three fixes in a row, only the last run completes; the superseded ones are cancelled mid-flight. This does not shorten a *single* run, it stops *wasting queue and minutes on runs whose result nobody will ever look at* — which is where the real time-to-feedback goes during active development.

(Honorable mentions already in place: the three units run as parallel jobs on separate runners — wall-clock = max, not sum; `GOTOOLCHAIN: local` guarantees no hidden toolchain downloads inside jobs.)

### B.3: Before / after

| Optimization applied | Before (s) | After (s) | Saving |
|----------------------|-----------:|----------:|-------:|
| golangci-lint binary cache (lint job) | 30 s | 21 s | −9 s |
| `GOFLAGS=-buildvcs=false` | (within run totals) | (within run totals) | ~1 s per compile |
| concurrency cancel-in-progress (series of pushes) | 3 × ~37 s queued | 1 × ~37 s (rest cancelled mid-flight) | ~2 runs saved |
| **Total wall-clock, single run (median of 3)** | **37** | **39** | **+2** |

### B.4: Bottleneck analysis

After every optimization, the single remaining dominant cost is **runner provisioning plus toolchain delivery**: the job-setup/checkout/`setup-go` sequence plus the linter install accounts for roughly 25–30 of the ~39 s total, while the *actual work* — `go vet` (4–11 s), `go test -race` (1–20 s) and the lint run inside a 16 s action step on a ~600-line zero-dependency module — is comparatively small. The honest headline of my own measurements: the bonus version does **not** beat v3 on a single run (median 39 s vs 37 s) — its wins live elsewhere: the linter-binary cache pays out from the *second* run on (the first of the three re-runs still downloads ~30 MB), `cancel-in-progress` saves queue time during push bursts, not run time, and job-to-job cloud noise (setup-go alone swings 1 s → 10 s between identical cells) is larger than any of the optimizations. To shorten a single run further by changing QuickNotes itself: almost nothing — code volume, not code quality, sets the floor; dropping `-race` is unacceptable (it is the requirement). The next meaningful jumps are pipeline-shape changes: a prebuilt image with Go 1.23/1.24 and golangci-lint baked in, or a self-hosted runner with a warm toolchain cache. I would stop optimizing at roughly **1 minute** wall-clock: below that, saved CI seconds cost more engineer-hours than they return, and the matrix already parallelizes everything that matters. 
---

## Appendix A — final `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
    paths: ['app/**', '.github/workflows/ci.yml', 'submissions/**']
  pull_request:
    branches: [main]
    paths: ['app/**', '.github/workflows/ci.yml', 'submissions/**']

permissions:
  contents: read

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  GOTOOLCHAIN: local
  GOFLAGS: -buildvcs=false

jobs:
  vet:
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        go: ['1.23', '1.24']
    defaults:
      run:
        working-directory: app
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - uses: actions/setup-go@d35c59abb061a4a6fb18e82ac0862c26744d6ab5  # v5.5.0
        with:
          go-version: ${{ matrix.go }}
          cache: true
          cache-dependency-path: app/go.mod
      - run: go vet ./...

  test:
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        go: ['1.23', '1.24']
    defaults:
      run:
        working-directory: app
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - uses: actions/setup-go@d35c59abb061a4a6fb18e82ac0862c26744d6ab5  # v5.5.0
        with:
          go-version: ${{ matrix.go }}
          cache: true
          cache-dependency-path: app/go.mod
      - run: go test -race -count=1 ./...

  lint:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - uses: actions/setup-go@d35c59abb061a4a6fb18e82ac0862c26744d6ab5  # v5.5.0
        with:
          go-version: '1.24'
          cache: false
      - uses: golangci/golangci-lint-action@4afd733a84b1f43292c63897423277bb7f4313a9  # v8.0.0
        with:
          version: v2.5.0
          working-directory: app

  ci-ok:
    if: always()
    needs: [vet, test, lint]
    runs-on: ubuntu-24.04
    steps:
      - run: |
          test "${{ contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled') }}" = "false"
```

## Appendix B — measurement methodology

For each scenario the workflow was pushed, waited to green, then re-run twice more with **Re-run all jobs** on the same commit (no extra commits — identical config and SHA), and the **median** of the three total wall-clock values recorded. Runner-to-runner variance is exactly why single measurements are not trusted (spec pitfall: "time the pipeline once and call it baseline").

## Screenshots

- `submissions/screenshots/lab3-01-green-run.png` — the PR's Checks tab with all units green (after the fix commit)
- `submissions/screenshots/lab3-02-red-blocked.png` — the deliberately broken run: red `test` output (`notes count: 1`) + "Merging is blocked"
- `submissions/screenshots/lab3-03-branch-protection.png` — ruleset `main-protection` with required status checks
- `submissions/screenshots/lab3-04-docs-skip.png` — the docs-only PR with zero workflow runs
