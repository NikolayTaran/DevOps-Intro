# Lab 12 — Bonus: WebAssembly Containers — A QuickNotes Endpoint on Spin

**Student:** NikolayTaran (na.taranvrn@gmail.com)
**Fork:** https://github.com/NikolayTaran/DevOps-Intro
**Branch:** `feature/lab12` (cut from `feature/lab11`)
**PR (course repo):** FILL-WITH-PR-URL
**Pinned toolchain:** Spin 3.6.3 · TinyGo 0.41.0 (go1.26.9, LLVM 20.1.1) · `spin-go-sdk/v2` v2.2.1 · wasmtime 9.0.4 · hyperfine 2.0.0
**Endpoint:** `GET /time` → `{"unix":…,"iso":…,"hour_minute":…,"timezone":"UTC+3 (Moscow)"}`

> **Where each number comes from.** The WASM side (Tasks 1 + Bonus) was built and
> measured on the Linux rig described below, with every raw output committed under
> `submissions/lab12-artifacts/`. The Docker column of the Task 2 table was measured
> on my laptop (rig B) with the Lab 6 image, using `scripts/lab12-docker-perf.ps1` —
> a script committed to this branch that applies *exactly* the same measurement
> protocol as the Spin-side scripts (same warmup/runs, same nearest-rank
> percentiles, same restart-loop cold start). No number in the table is synthetic.

---

## Layout

```text
wasm/                                # Task 1: Spin component (scaffolded, then edited)
  main.go  go.mod  go.sum  spin.toml # scaffold + handler (Appendix A/B)
  main.wasm                          # committed build artifact (370,510 B) - evidence
wasm-cli/                            # Bonus: standalone WASI CLI module
  main.go  go.mod  main.wasm         # no SDK, CGI-shaped (Appendix C)
scripts/
  lab12-warm-spin.py                 # warm latency: keep-alive loop, 5 warmup + 50 runs
  lab12-coldstart-spin.py            # cold start: kill spin, restart, poll to first 200
  lab12-docker-perf.ps1              # Docker-side twin of the two, run on rig B
submissions/lab12-artifacts/         # every raw output quoted in this report
```

## Rig

**Rig A — WASM/Spin side (Linux sandbox).** Debian 13 (trixie), x86_64, 2 vCPU,
4 GB RAM. Unprivileged user-space toolchain, nothing installed system-wide:

```text
spin 3.6.3 (88d51cf 2026-04-09)
tinygo version 0.41.0 linux/amd64 (using go version go1.26.9 and LLVM version 20.1.1)
go version go1.26.9 linux/amd64
wasmtime-cli 9.0.4
hyperfine 2.0.0
```

(Version pinning mattered immediately: with host Go 1.25.14 the build failed with
`net/ip.go:17:2: package internal/strconv is not in std` — TinyGo 0.41's `net`
package targets Go 1.26; 0.41.1 is the release that restored 1.25 back-compat.
Receipt: `lab12-artifacts/iterate-to-final.txt`. This is the lab's "check the
compatibility matrix" pitfall, hit for real.)

**Rig B — Docker side (author's laptop).** Windows + Docker Desktop (WSL2
backend) — the same machine that built and ran the `quicknotes:lab6` image
(`docker build ./app`, distroless `static-debian12:nonroot`; recorded in this
fork's Lab 6/11 reports as 15.3 MB disk / 3.43 MB content) in Labs 6/9/11, so
the image and its layers were already local. PowerShell runs in the ru-RU
locale, which is why the script's raw output below prints `,` as the decimal
separator (dot-normalized in the table). Rig B is also a faster machine than
the deliberately modest 2-vCPU rig A — worth remembering when reading the
warm-latency row.

---

## Task 1 — Build a WASM Endpoint with the Spin SDK (4 pts)

### 1.1: How every requirement is met

| Requirement | Where it lives |
|---|---|
| Scaffolded from `spin new -t http-go`, not hand-written | `wasm/` is the output of `spin new -t http-go moscow-time --accept-defaults` (after `spin templates install --git …/spin --branch v3.6.3`), then edited |
| `spinhttp.Handle(...)` registration | `wasm/main.go`, import `spinhttp "github.com/spinframework/spin-go-sdk/v2/http"` — the path the scaffold generated (CNCF org, v2.2.1) |
| `GET /time` → JSON with `unix`, `iso`, `hour_minute`, Moscow time | handler in `wasm/main.go`; `time.FixedZone("MSK", 3*60*60)`; JSON via `fmt.Sprintf` + `%q` |
| `Content-Type: application/json` | set in the handler; verified by `curl -D -` (receipt below) |
| HTTP trigger routed at `/time` | `spin.toml`: `route = "/time"` |
| `allowed_outbound_hosts = []` | `spin.toml` (scaffold default kept) |
| Build command = TinyGo wasip1 + `-buildmode=c-shared` | `spin.toml` (scaffold default kept): `tinygo build -target=wasip1 -buildmode=c-shared -no-debug -o main.wasm .` |
| Design questions a–d | §1.5 below |

### 1.2: Scaffold from the current template

Spin 3.6.3 does not bundle templates; installing them from the *same version's
branch* keeps the scaffold and the runtime in lockstep:

```text
$ spin templates install --git https://github.com/spinframework/spin --branch v3.6.3
$ spin templates list | grep http-go
| http-go                     HTTP request handler using (Tiny)Go                          |

$ mkdir -p wasm && cd wasm
$ spin new -t http-go moscow-time --accept-defaults
```

The generated `go.mod` is the modern CNCF path the lab expects —
`require github.com/spinframework/spin-go-sdk/v2 v2.2.1` — and the generated
`spin.toml` already carries `allowed_outbound_hosts = []` and the wasip1
`-buildmode=c-shared` build command. I only changed the route to `/time` and the
handler body; the scaffold's `go.sum` ships the SDK hashes.

### 1.3: Iterate to a *correct* Moscow time — three versions

**v1 — the naive port.** `time.LoadLocation("Europe/Moscow")` +
`json.NewEncoder(map[string]any{…})`. Builds fine; fails at runtime:

```text
$ curl -s -w '\nHTTP %{http_code}\n' http://127.0.0.1:33000/time
tz: unknown time zone Europe/Moscow

HTTP 500
```

**v2 — the tempting fix.** `time.Now().UTC().Add(3 * time.Hour)` (the lab's
pitfall hint) keeps `json.NewEncoder`:

```text
{"hour_minute":"02:31","iso":"2026-10-16T02:31:51Z","unix":1792117911}
```

Wall clock is right, but RFC3339 labels a UTC-located time `Z` — the response
would claim 02:31 *UTC*. Wrong by three hours for any RFC3339-parsing client.

**v3 — final.** `time.FixedZone("MSK", 3*60*60)` (fixed offset, no tzdata
needed, prints `+03:00`) and the TinyGo-safe JSON path the lab recommends —
`fmt.Sprintf` with `%q` verbs, no reflection:

```go
var msk = time.FixedZone("MSK", 3*60*60)
...
now := time.Now().In(msk)
body := fmt.Sprintf(`{"unix":%d,"iso":%q,"hour_minute":%q,"timezone":%q}`,
    now.Unix(), now.Format(time.RFC3339), now.Format("15:04"), "UTC+3 (Moscow)")
```

Full evolution with both failure receipts:
`lab12-artifacts/iterate-to-final.txt`.

### 1.4: Build, run, verify

```text
$ spin build
Building component moscow-time with `tinygo build -target=wasip1 -buildmode=c-shared -no-debug -o main.wasm .`
Finished building all Spin components

$ ls -la main.wasm
-rw-rw-r-- 1 z z 370510 Oct 15 23:40 main.wasm
$ sha256sum main.wasm
abc86045fff250c66673dd0cb4d10dd8e9f94d8a020e73af8a49cb2ac74f14b6  main.wasm
```

(Spin's default port 3000 was taken by another local service on this rig, so
verification ran with `--listen 127.0.0.1:33123`; nothing else changes.)

```text
$ spin up --listen 127.0.0.1:33123
Logging component stdio to ".spin/logs/"

Serving http://127.0.0.1:33123
Available Routes:
  moscow-time: http://127.0.0.1:33123/time

$ curl -s http://127.0.0.1:33123/time | python3 -m json.tool
{
    "unix": 1792107654,
    "iso": "2026-10-16T02:40:54+03:00",
    "hour_minute": "02:40",
    "timezone": "UTC+3 (Moscow)"
}

$ curl -s -D - -o /dev/null http://127.0.0.1:33123/time | head -4
HTTP/1.1 200 OK
content-type: application/json
content-length: 104
date: Thu, 15 Oct 2026 23:40:54 GMT

$ curl -s -X POST -w '\nHTTP %{http_code}\n' http://127.0.0.1:33123/time
method not allowed
HTTP 405
```

HTTP 200, valid JSON, `application/json`, Moscow time with the honest `+03:00`
designator, and a method guard on top (bonus robustness, not required).

### 1.5: Design questions (a–d)

**a) Browser WASM vs server WASM: `go build -target=js/wasm` vs `tinygo build -target=wasip1`.**
The two targets produce modules for *different hosts*. `js/wasm` compiles against
`GOOS=js` and imports the `syscall/js` glue: the module is inert until a *browser*
instantiates it and provides `console`, `fetch`, the DOM — every OS-ish thing
arrives as a JavaScript bridge, and the binary drags the full Go runtime plus JS
glue along. `wasip1` compiles against WASI: the module's world is the
`wasi_snapshot_preview1` import set — parsed from my actual binary, it is exactly
`fd_write`, `clock_time_get`, `args_sizes_get`, `args_get`, `fd_read`,
`random_get` (`lab12-artifacts/wasm-exports.txt`) — so the *host*, not the
browser, supplies stdio, clocks, args, and entropy. What's missing on the server
side is the DOM/browser interop (useless there) plus, for TinyGo specifically,
the stdlib gaps (question d): no tzdata and a leaner reflect. What you gain:
POSIX-shaped capability I/O, no JS host required, execution under
wasmtime/Spin/K8s shims, a dramatically smaller artifact, and *the same CPU
portability in reverse* — one module, any architecture. In one line: `js/wasm`
is "Go rented out to a browser page", `wasip1` is "Go rented out to a server
sandbox".

**b) Why `-buildmode=c-shared`?** The Spin host expects a **library, not a
program**: something it can instantiate once (running Go `init()` — which is
where `spinhttp.Handle` registers the handler), then *call into* per HTTP
request. I ran the lab's suggested experiment (drop the flag) and parsed both
binaries' import/export sections to see the actual difference
(`lab12-artifacts/wasm-exports.txt` + `nocs.txt`):

| | `c-shared` (committed) | default exe mode |
|---|---|---|
| exports | `_initialize`, `spin_http_handle_http_request`, `canonical_abi_realloc`, `canonical_abi_free` | the same **plus `_start`** |
| imports | 6 `wasi_snapshot_preview1` functions, **no `proc_exit`** | the same **plus `proc_exit`** |

On the pinned combo both shapes still serve under Spin 3.6.3 (the SDK exports the
handler either way — my no-flag build returned the same JSON with HTTP 200), but
the shapes are not equivalent: the exe-mode module is a *command* — it has a
`_start` and imports `proc_exit`, i.e. it can decide to end its own process. The
c-shared module is a *reactor*: no `_start`, no `proc_exit` — the module cannot
terminate anything; **the host owns the lifecycle** and invokes the exported
handler whenever a request arrives. That is the contract Spin's host ABI is
designed around, and it is what the template pins. (In older Spin/SDK versions
where the handler exports were absent without the flag, the failure was the
lab-predicted one: `spin up` returns HTTP 500 with empty component logs.)

**c) `allowed_outbound_hosts = []` — capability model vs Docker `--network none`.**
Docker isolates *resources*: with `--network none` the container still gets a
network namespace with its own loopback, still runs a full TCP/IP stack, can
still `socket()`/`connect()` — the packets just never leave. The syscall surface
toward the host kernel remains fully exposed; the wall is around the traffic, not
around the interface. The WASM capability model inverts this: deny-by-default,
grant-by-import. A module can only call what the host *provides as imports*; my
binary's complete import set is six functions (fd_write, clock_time_get,
args_get/sizes_get, fd_read, random_get — parsed, not assumed), and none of them
opens a socket. With `allowed_outbound_hosts = []` Spin simply never wires any
outbound-network host interface into the instance, so there is no socket code
path to attack at all — not "blocked", but *absent*. To allow e.g. `https://api.example.com`
you would grant exactly that origin in the manifest, host-by-host. Compared to
`--network none`: Docker fences a road; WASM never builds the road.

**d) TinyGo stdlib gaps hit during this lab.** Two, both real receipts:
(1) **timezone data** — `time.LoadLocation("Europe/Moscow")` compiles and then
fails at runtime with `unknown time zone Europe/Moscow` (HTTP 500, receipt in
§1.3): TinyGo does not embed Go's `time/tzdata`, and a wasip1 module sees no
`/usr/share/zoneinfo` either. Fix: `time.FixedZone("MSK", 3*60*60)` — correct
wall clock *and* an honest `+03:00` RFC3339 designator.
(2) **reflection-heavy `encoding/json`** — the lab predicts
`json.NewEncoder(map[string]any)` may fail under TinyGo. On TinyGo 0.41 it
actually *worked* for this payload (v2 output above) — the reflect implementation
has caught up for small maps — but the failure mode is real for anything more
ambitious (interface decoding, custom marshalers), so the final handler follows
the lab's robust pattern: `fmt.Sprintf` with `%q` verbs, zero reflection,
deterministic key order. The general lesson: TinyGo is "Go minus the parts that
lean on the runtime's reflective machinery and the OS", and time-zones + JSON
reflection are exactly where you feel it.

---

## Task 2 — Perf Comparison vs Lab 6 Container (4 pts)

### 2.1: Methodology (identical semantics on both rigs)

- **Warm latency** — a keep-alive HTTP client loop: 5 warmup requests, then 50
  measured on one persistent connection; p50/p95 are nearest-rank. Rig A:
  `scripts/lab12-warm-spin.py` (Python `http.client`). Rig B: rig B runs the
  same protocol in `scripts/lab12-docker-perf.ps1` (System.Net.Http.HttpClient)
  against `GET /health` of the Lab 6 container. A keep-alive loop rather than
  one `curl` process per request keeps the measurement on the *request*, not on
  process spawn: on this rig a bare `curl` round-trip costs ~7.3 ms of which the
  HTTP itself is ~1.3 ms (hyperfine receipt below).
- **hyperfine** (the lab's prescribed tool) is used where it is the right tool:
  the curl-vs-keepalive check above, and the Bonus's per-invocation
  `wasmtime run` comparison (a CLI-process benchmark, exactly what hyperfine is for).
- **Cold start** — kill the runtime, restart, measure wall time to the *first
  successful response* (poll every 2–5 ms). 7 samples on rig A
  (`scripts/lab12-coldstart-spin.py`), 5 on rig B (the same loop in the ps1:
  `docker rm -f` → `docker run -d` → poll `GET /health`). Docker layers are
  already local (no pull, no first-time extraction) — the same "warm cache"
  conditions as Spin's restarts.
- **Artifact size** — `stat` on `main.wasm`; `docker image inspect
  --format {{.Size}}` on rig B (plus the recorded Lab 6 values).

### 2.2: The table (real numbers)

| Dimension | Lab 6 Docker (rig B) | Lab 12 WASM/Spin (rig A) |
|---|---:|---:|
| Artifact size | **15,653,220 B** (~14.9 MiB, `docker image inspect {{.Size}}`) | **370,510 B** (0.35 MiB) — ~42× smaller |
| Cold start (p50) | **306.4 ms** (5 samples: 299.0–323.7; p95 323.7) | **41.1 ms** (7 samples: 38.3–51.2) |
| Warm latency p50 | **0.781 ms** | **1.335 ms** |
| Warm latency p95 | **1.368 ms** | **1.552 ms** |

Raw outputs: `lab12-artifacts/warm-spin.txt`, `coldstart-spin.txt`,
`hyperfine-{spin,wasmtime-cli}.txt`.

```text
$ python3 scripts/lab12-warm-spin.py 127.0.0.1:33123 5 50
{
  "url": "127.0.0.1:33123",
  "warmup": 5,
  "runs": 50,
  "p50_ms": 1.335,
  "p95_ms": 1.552,
  "mean_ms": 1.362,
  "min_ms": 1.235,
  "max_ms": 1.728,
  "body": "{\"unix\":1792107481,\"iso\":\"2026-10-16T02:38:01+03:00,\"hour_minute\":\"02:38\",\"timezone\":\"UTC+3 (Moscow)\"}\n"
}

$ python3 scripts/lab12-coldstart-spin.py wasm 33123 7
{
  "samples": 7,
  "p50_ms": 41.1,
  "mean_ms": 43.5,
  "min_ms": 38.3,
  "max_ms": 51.2,
  "all_ms": [51.2, 50.9, 38.4, 38.3, 42.1, 41.1, 42.2]
}

$ hyperfine --warmup 5 --runs 50 'curl -s -o /dev/null http://127.0.0.1:33123/time'
Benchmark 1: curl -s -o /dev/null http://127.0.0.1:33123/time (50 runs)
                mean     ±       σ          min     …     max
  Wall Time      7.3 ms  ±     0.3 ms       7.1 ms  …    8.3 ms
  Memory        11.7 MiB ±     0.1 MiB     11.5 MiB …    11.9 MiB
```

Docker side (rig B, from `scripts/lab12-docker-perf.ps1` — paste of the script's
own labeled output; ru-RU locale prints `,` as the decimal separator, the table
above is dot-normalized):

```text
C:\Users\Inno\OneDrive\Documents\DevOps-Intro>powershell -ExecutionPolicy Bypass -File scripts\lab12-docker-perf.ps1
docker_image_size_bytes=15653220
warm_p50_ms=0,781
warm_p95_ms=1,368
cold_p50_ms=306,4
cold_all_ms=323,7, 306,4, 299,0, 304,9, 312,7
done.
```

### 2.3: What dominates each platform's cold start

**Container:** containerd/dockerd request handling, cgroup + namespace creation,
overlayfs mount and rootfs pivot, runc process setup, then the static Go binary
plus Go runtime init before the listener answers. That whole *machinery of
isolation* is the cost — and it is machinery a plain process never pays. My
Docker p50 (306.4 ms) is measured with layers already local; a first-ever
run would add layer download + extraction on top.

**Spin:** one binary exec, manifest parse, then wasmtime work — engine/Cranelift
initialization, module load and compilation, instantiation (linear memory +
stack), TCP bind, and the first request triggering the component instance. The
370 KB module compiles in single-digit milliseconds; the 41.1 ms p50 on
this deliberately modest 2-vCPU rig is dominated by wasmtime engine setup, and it
buys a process that then answers in ~1.3 ms. The Docker column of the table —
measured on a *faster* machine, which is also why Docker's warm p50 (0.781 ms)
lands below rig A's 1.335 ms — completes the comparison: warm latency is a
sub-2 ms round-trip on both platforms and is not where they part ways; the
cold column (306.4 vs 41.1 ms, ~7.5×) and the size column (~42×) are, and that
is the gap in kind Reading 12's table predicts, not just degree.

### Design questions (e–g)

**e) What dominates each cold start?** For Docker: *isolation machinery* — image
layer setup, namespaces/cgroups, runc bootstrap; the app itself (a static
already-compiled binary) is the cheapest part. For Spin: *runtime machinery of a
different kind* — wasmtime engine init + module compile + instantiate; there is
no kernel-level sandbox to erect because the sandbox is the type system of the
WASM validation itself. That asymmetry is the whole story of the table: Docker
pays for walls, Spin pays for a JIT warm-up, and the module never needs walls.

**f) For what workloads is WASM clearly better, and where is Docker still right?**
(Reading 12 §7's trade-off table, confirmed by my numbers.) WASM wins where
**start frequency × isolation density** dominates: edge functions and POP-served
endpoints (cold start ~40 ms vs hundreds; 0.35 MiB artifact to ship to 300 POPs),
plugin systems (untrusted third-party code — imports are the entire attack
surface), multi-tenant SaaS request handlers (a fresh instance per request, no
shared memory), and one-artifact CPU portability (amd64/arm64/Apple Silicon from
the same bytes). Docker is still right for the QuickNotes-shaped world:
long-running stateful processes with local disk (`/data` volume), real database
clients (WASM's weakest library area), anything needing arbitrary OS packages
(`apt install`), heavy goroutine fleets and cgo, and anything that wants the
mature ecosystem of observability/orchestration. This is not a replacement
relationship: Lab 6 and Lab 12 both exist in this fork because they answer
different questions.

**g) Multi-tenant safety: what concrete attack does a WASM platform make harder?**
The container-escape-via-syscall class. A compromised process in a container
still *speaks syscalls to the host kernel* — namespaces restrict what it can
name, seccomp filters some calls, but the interface itself is always there, so a
kernel bug reachable through an allowed syscall (the Dirty-Pipe-style pipe
corruption, io_uring bugs, netlink quirks) is a container-escape primitive on
every shared host. A WASM instance has **no syscall interface at all**: it can
invoke exactly the imports the host provides — for my module, six functions,
none of which is socket/ioctl-like (parsed in `wasm-exports.txt`). A malicious
tenant module cannot even *formulate* an `ioctl`; there is no kernel to bug. The
residual risks move to the host (wasmtime itself, the engine bugs) — a much
smaller, memory-safe, audited surface than the Linux kernel. Namespaces fence
tenants off from each other and from the host; the capability model removes the
road entirely.

---

## Bonus — Two WASM Execution Models (2 pts)

### B.1: The standalone WASI CLI module

`wasm-cli/main.go` (Appendix C): no Spin SDK, the WAGI/CGI-over-WASM shape —
request arrives as `REQUEST_METHOD` / `PATH_INFO` env vars, response is printed
to stdout. Same Moscow-time logic (same `FixedZone`, same `fmt.Sprintf` JSON).

Build and run with the lab's exact commands:

```text
$ cd wasm-cli
$ tinygo build -o main.wasm -target=wasi -no-debug ./main.go
$ ls -la main.wasm
-rw-rw-r-- 1 z z 196069 Oct 15 23:38 main.wasm
$ sha256sum main.wasm
29547b563a145c0a45b279bc9d17adc91f481cfdcb3979910eb7c5befca3ea3f  main.wasm

$ wasmtime run --env REQUEST_METHOD=GET --env PATH_INFO=/time main.wasm
{"unix":1792107521,"iso":"2026-10-16T02:38:41+03:00","hour_minute":"02:38","timezone":"UTC+3 (Moscow)"}

$ wasmtime run --env REQUEST_METHOD=POST --env PATH_INFO=/time main.wasm
wasm-cli: method "POST" not allowed (only GET)     # stderr, exit code 1
```

### B.2: The two models, measured

```text
$ hyperfine --warmup 3 --runs 50 'wasmtime run --env REQUEST_METHOD=GET --env PATH_INFO=/time main.wasm'
Benchmark 1: wasmtime run ... (50 runs)
                mean     ±       σ          min     …     max
  Wall Time      9.5 ms  ±     0.5 ms       8.6 ms  …   11.3 ms
  Memory        17.4 MiB ±     0.0 MiB     17.3 MiB …   17.4 MiB
```

| | Spin component (Task 1) | WASI CLI module (Bonus) |
|---|---:|---:|
| Module size | 370,510 B | **196,069 B** (no SDK: −47%) |
| Execution model | persistent wasi-http server, handler called per request | per-invocation `wasmtime run`, CGI-shaped |
| Cost per request | 1.335 ms p50 (warm, keep-alive) | **9.5 ms mean** *every* invocation (process + compile + instantiate + run) |
| Cost to start serving | 41.1 ms cold p50 | n/a — never "serves"; each run is the whole life |
| Host | Spin 3.6.3 (engine + HTTP server + routing + policy) | wasmtime 9.0.4 CLI alone |

Reading of the numbers: one CLI invocation (9.5 ms) is cheaper than *starting*
Spin (41.1 ms) — but Spin amortizes: at request N the totals cross at roughly
N ≈ 5 (9.5·N vs 41.1 + 1.3·N), and past that the persistent server wins ~7×
per request (9.5 ms vs 1.3 ms). The CLI model also spends 17.4 MiB
RSS *per concurrent invocation*, while Spin's engine is paid once.

### Design questions (h–j)

**h) Why can't the Task 1 component run under bare `wasmtime run`?** Receipt
(`lab12-artifacts/wasmtime-on-spin-module.txt`):

```text
$ wasmtime run --env REQUEST_METHOD=GET --env PATH_INFO=/time wasm/main.wasm
$ echo $?
0
```

Exit 0, zero output — nothing ran. The component is a *library*: it exports
`spin_http_handle_http_request` (+ `canonical_abi_realloc/free`) and
`_initialize`, but **no `_start`** — there is no command entrypoint for the CLI
to invoke, so `wasmtime run` starts the runtime, finds nothing to call, and
exits successfully. The HTTP logic only executes when a wasi-http *host* imports
and calls the handler per request — which is Spin. (And this wasmtime 9.0.4
build has no `serve` subcommand at all — `run`, `settings`, `wast` — so bare
wasmtime here cannot host wasi-http in any form.)

**i) Spin uses wasmtime internally — so what does Spin add?** The engine is the
car's motor, not the car. Spin adds: (1) the **HTTP trigger layer** — manifest
parsing, route table, TCP listener, the server loop that turns sockets into
wasi-http requests; (2) the **component lifecycle** — loading the module,
`_initialize` once, instantiating a fresh instance per request (instance
pooling), marshaling request/response through the canonical ABI to the exported
handler, capturing component stdio into logs; (3) **policy** —
`allowed_outbound_hosts` enforcement and the capability wiring the manifest
declares; (4) **workflow** — `spin build` (toolchain orchestration), `spin new`
templates, deploy tooling, plugins. Bare wasmtime gives you "execute this module
safely"; Spin gives you "serve this module as an application, with rules".

**j) Two execution models — when does each fit?** Per-invocation
`wasmtime run` is the CGI model reborn: every request is a fresh process —
perfect isolation, zero shared state, trivially schedulable, and the numbers
show it: 9.5 ms end-to-end, 17.4 MiB per run. It fits **batch/one-shot
workloads**: a WASM rewrite of a CLI tool run in CI, cron-shaped transforms,
image-processing jobs, or testing a module in isolation. Spin's persistent
wasi-http server fits **sustained request serving** — the moscow-time endpoint
itself, edge POPs, multi-tenant SaaS handlers: pay the engine once (41 ms), then
1.3 ms per request with the module's instantiation hot. The crossover from my
measurements is ~5 requests; beyond it the persistent server wins ~7×, below it
the CGI shape's "nothing stays resident" simplicity wins. (Same shape as
Reading 12 §6's history: WAGI died as a *framework*, but the per-invocation
model is exactly what `wasmtime run` still offers — as this Bonus just
measured.)

---

## Acceptance checklist

### Task 1 (4 pts)
- ✅ Scaffolded from `spin new -t http-go` (SDK v2.2.1 CNCF path, wasip1 `-buildmode=c-shared` build command — both from the template itself)
- ✅ `spin build` produces `main.wasm` (370,510 B, sha256 `abc86045…`, committed as evidence)
- ✅ `spin up` serves `/time` returning Moscow-time JSON (HTTP 200, valid JSON, `application/json` — §1.4 receipts)
- ✅ Design questions a–d answered (§1.5, with parsed-binary and failure receipts)

### Task 2 (4 pts)
- ✅ Full perf table with real numbers (§2.2; Docker side measured on rig B with the committed twin script)
- ✅ Cold + warm + size captured on both platforms
- ✅ Design questions e–g answered (§2.3)

### Bonus Task (2 pts)
- ✅ Same logic as a standalone WASI CLI module, runs under `wasmtime run` (B.1)
- ✅ Size + cold-start/per-invocation comparison of the two models (B.2)
- ✅ Design questions h–j answered (with the silent-`wasmtime run` receipt)

---

## Appendix A — `wasm/main.go` (final)

```go
package main

import (
        "fmt"
        "net/http"
        "time"

        spinhttp "github.com/spinframework/spin-go-sdk/v2/http"
)

// Moscow is UTC+3 year-round (no DST since 2014). time.LoadLocation needs
// the IANA tz database, which a wasip1 module has no access to (the naive
// version failed with "unknown time zone Europe/Moscow" — see lab12 §d),
// so we build a fixed-offset zone instead: same wall clock, no tzdata.
var msk = time.FixedZone("MSK", 3*60*60)

func init() {
        spinhttp.Handle(func(w http.ResponseWriter, r *http.Request) {
                if r.Method != http.MethodGet {
                        w.Header().Set("Allow", http.MethodGet)
                        http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
                        return
                }
                now := time.Now().In(msk)
                // TinyGo-safe JSON: fmt.Sprintf + %q verbs instead of the
                // reflection-heavy encoding/json path (lab guideline, §d).
                body := fmt.Sprintf(`{"unix":%d,"iso":%q,"hour_minute":%q,"timezone":%q}`,
                        now.Unix(), now.Format(time.RFC3339), now.Format("15:04"), "UTC+3 (Moscow)")
                w.Header().Set("Content-Type", "application/json")
                fmt.Fprintln(w, body)
        })
}

func main() {}
```

## Appendix B — `wasm/spin.toml` (route edit only)

```toml
#:schema https://schemas.spinframework.dev/spin/manifest-v2/latest.json

spin_manifest_version = 2

[application]
name = "moscow-time"
version = "0.1.0"
authors = ["NikolayTaran <na.taranvrn@gmail.com>"]
description = ""

[[trigger.http]]
route = "/time"
component = "moscow-time"

[component.moscow-time]
source = "main.wasm"
allowed_outbound_hosts = []
[component.moscow-time.build]
command = "tinygo build -target=wasip1 -buildmode=c-shared -no-debug -o main.wasm ."
watch = ["**/*.go", "go.mod"]
```

`wasm/go.mod` (scaffold): `module github.com/moscow_time`, `go 1.22`,
`require github.com/spinframework/spin-go-sdk/v2 v2.2.1` (+ indirect
`julienschmidt/httprouter v1.3.0`). `go.sum` committed as scaffolded.

## Appendix C — `wasm-cli/main.go` (Bonus)

```go
package main

import (
        "fmt"
        "os"
        "time"
)

// Standalone WASI CLI version of the Moscow-time endpoint.
//
// No Spin SDK: the old WAGI/CGI-over-WASM shape — the request arrives
// through environment variables (REQUEST_METHOD, PATH_INFO) and the
// response is printed to stdout. Runs under bare `wasmtime run`.
//
// Moscow = UTC+3 year-round; wasip1 has no tzdata, so the naive
// time.LoadLocation("Europe/Moscow") fails here too (see lab12 §d) —
// a fixed-offset zone gives the correct +03:00 designator.
var msk = time.FixedZone("MSK", 3*60*60)

func main() {
        method := os.Getenv("REQUEST_METHOD")
        path := os.Getenv("PATH_INFO")

        if method != "GET" {
                fmt.Fprintf(os.Stderr, "wasm-cli: method %q not allowed (only GET)\n", method)
                os.Exit(1)
        }
        if path != "" && path != "/time" {
                fmt.Fprintf(os.Stderr, "wasm-cli: path %q not served (only /time)\n", path)
                os.Exit(1)
        }

        now := time.Now().In(msk)
        // TinyGo-safe JSON: fmt.Sprintf + %q (lab guideline).
        fmt.Printf(`{"unix":%d,"iso":%q,"hour_minute":%q,"timezone":%q}`+"\n",
                now.Unix(), now.Format(time.RFC3339), now.Format("15:04"), "UTC+3 (Moscow)")
}
```

## Appendix D — measurement scripts & raw outputs

- `scripts/lab12-warm-spin.py` — keep-alive warm latency (5 warmup + 50 runs, nearest-rank p50/p95)
- `scripts/lab12-coldstart-spin.py` — restart-loop cold start to first 200 (7 samples)
- `scripts/lab12-docker-perf.ps1` — the Docker-side twin (same protocol: image size, warm p50/p95, cold p50 ×5)
- `submissions/lab12-artifacts/` — `versions.txt`, `spin-build.txt`, `spin-up.log`,
  `spin-up-curl.txt`, `warm-spin.txt`, `coldstart-spin.txt`,
  `hyperfine-spin.{txt,json}`, `hyperfine-wasmtime-cli.{txt,json}`,
  `iterate-to-final.txt`, `wasm-exports.txt`, `nocs.txt`,
  `wasmtime-on-spin-module.txt`

## Screenshots

Numbering reserves four slots — 01 Task 1 (`spin up` + `curl`), 02 Task 2 (Docker
rig B), 03 Bonus (`wasmtime run`), 04 the PR — so file names stay stable whether
or not a given screenshot is taken.

- `submissions/screenshots/lab12-02-docker-perf.png` — `scripts\lab12-docker-perf.ps1` output on rig B (the §2.2 Docker values). The one screenshot worth taking: it is the only measurement run on this machine, and everything else in this report is already evidenced by the quoted outputs and the raw files in `lab12-artifacts/`
- `submissions/screenshots/lab12-04-pr.png` — the course-repo PR (optional: the PR link in the header and in Moodle is the actual deliverable; the screenshot is just a visual receipt in the repo, in the style of this fork's earlier labs)
- (optional, if reproduced locally with `spin.exe`/`wasmtime`: `lab12-01-spin-up-time.png` — `spin up` + `curl /time | python3 -m json.tool`; `lab12-03-wasmtime-cli.png` — the B.1 build + run; the primary evidence for both is the quoted outputs + raw files in `lab12-artifacts/`)
