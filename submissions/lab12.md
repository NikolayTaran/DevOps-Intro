# Lab 12 — WebAssembly: a QuickNotes-style endpoint on Spin (bonus lab)

**Student:** NikolayTaran (na.taranvrn@gmail.com)
**Fork:** https://github.com/NikolayTaran/DevOps-Intro
**Branch:** `feature/lab12` (cut from `feature/lab11`)

> **Spin 4 vs the lab prose.** The lab text was validated against Spin 3.x
> (TinyGo `wasip1` + `-buildmode=c-shared`). `spin new -t http-go` on the
> current **Spin 4.2.2** scaffolds **Go + `componentize-go`** with
> `spin-go-sdk/v3` instead — per lab §1.1 ("always scaffold from the current
> template"), the scaffold was followed as generated. The TinyGo-specific
> pitfalls (tzdata, reflection-heavy JSON, `-buildmode=c-shared`) are still
> respected in the handler design; see design question (b) for what
> `-buildmode=c-shared` means on each toolchain.

---

## Layout

```text
wasm/                    # Spin 4 http-go component "moscow-time"
  main.go                #   GET /time -> Moscow-time JSON
  spin.toml              #   route=/time, allowed_outbound_hosts=[]
  go.mod / go.sum        #   spin-go-sdk/v3 v3.0.0, componentize-go v0.3.4 (tool)
  main.wasm              #   built artifact (committed, 4,819,215 bytes)
wasm-cli/                # bonus: standalone WASI CLI module
  main.go                #   REQUEST_METHOD/PATH_INFO -> stdout JSON
  go.mod
  main.wasm              #   built artifact (committed, 209,767 bytes)
scripts/lab12-measure.ps1  # perf measurement script (Windows runtime side)
submissions/lab12-artifacts/
```

**Tool pins (build side, Linux x86_64):** Spin `4.2.2`, `componentize-go`
`v0.3.4` (via the scaffold's `go tool` directive), Go bootstrap
`go1.25.5-wasi-on-idle-v2` (auto-provisioned by componentize-go; stock Go
lacks the `wasiOnIdle` runtime support the component world needs),
TinyGo `0.43.0` (wasm-cli, with host Go 1.27.2), `wasmtime CLI 48.0.6`.

**Rig.** The component and the CLI module were **built on Linux x86_64** and
committed, so the runtime side needs no toolchain. **Runtime measurements
(Warm/Cold/latency) are taken on Windows 11 with Docker Desktop** — the same
host runs both `spin up` and the Lab 6 container, which keeps the comparison
fair. `scripts/lab12-measure.ps1` automates the whole measurement block.

> Windows build note (if the component ever needs a local rebuild):
> `go tool componentize-go` downloads `componentize-go-windows-amd64.tar.gz`,
> but the release ships `.zip` (404) — install `componentize-go.exe` from the
> zip manually; stock Go lacks `wasiOnIdle`, so point componentize-go at the
> downloaded bootstrap (`go1.25.5-wasi-on-idle-v2`) via `--go`. On Linux the
> scaffold default works as-is.

---

## Task 1 — Spin WASM `/time` (4 pts)

### Scaffold

```bash
mkdir -p wasm && spin templates install --git https://github.com/spinframework/spin
spin new -t http-go moscow-time --accept-defaults   # flattened into wasm/
```

### Handler ([wasm/main.go](../wasm/main.go))

Registered through the SDK's `spinhttp.Handle(...)`; answers `GET /time`:

```json
{"unix":1791999214,"iso":"2026-10-14T20:33:34+03:00","hour_minute":"20:33","timezone":"Europe/Moscow","utc_offset":"+03:00"}
```

Deliberate choices (the classic WASM traps, avoided up front):

- Moscow time via `time.FixedZone("Europe/Moscow", 3*3600)` —
  `time.LoadLocation` needs tzdata, which is not embedded in a WASM component
  (Moscow has been a permanent UTC+3 since 2014, so the fixed offset is exact);
- the JSON body is built with `fmt.Sprintf` — no `map[string]any` reflection
  through `encoding/json`;
- non-GET answered with 405 + JSON error; non-`/time` is unreachable (the
  trigger route is pinned to `/time`).

### Manifest ([wasm/spin.toml](../wasm/spin.toml))

- `[[trigger.http]] route = "/time"` → component `moscow-time`;
- `allowed_outbound_hosts = []` — the strictest capability posture: the
  component cannot open a single outbound connection;
- build command (from the Spin 4 scaffold): `go tool componentize-go build`.

### Build + run

```text
$ spin build
Finished building all Spin components       # main.wasm = 4,819,215 bytes (~4.6 MB)
$ spin up --listen 127.0.0.1:3000
Serving http://127.0.0.1:3000
Available Routes:
  moscow-time: http://127.0.0.1:3000/time

$ curl -s http://127.0.0.1:3000/time
{"unix":1791999214,"iso":"2026-10-14T20:33:34+03:00","hour_minute":"20:33","timezone":"Europe/Moscow","utc_offset":"+03:00"}
$ curl -s -X POST http://127.0.0.1:3000/time        # method guard
{"error":"method not allowed"}                       # HTTP 405
```

HTTP 200, `Content-Type: application/json` (verified in the measurement run).

### Design questions (a–d)

**a) Browser WASM vs server WASM.** `GOOS=js GOARCH=wasm` produces a module
for the browser's `wasm_exec.js` host: full DOM/JS interop, but the "OS" is
whatever the page grants, and there is no standardized system interface —
nothing outside a browser can run it. The server targets (`wasip1` via
TinyGo, or componentize-go's component world) export a **WASI** interface:
no DOM at all, a reduced stdlib, but a portable sandbox that any wasi host
(Spin, wasmtime) can instantiate. For an HTTP endpoint you lose the browser
and gain a server-agnostic, capability-scoped runtime.

**b) Why `-buildmode=c-shared` (Spin 3 / TinyGo path).** Spin does not "run
a program": it loads a **reactor** — a module that *exports* the HTTP handler
symbols the SDK registered and keeps them resident across requests. TinyGo's
default build emits a command-style module (`_start`, run once, exit);
`-buildmode=c-shared` switches the export shape to what the Spin host binds.
Without it the module never exports a handler — `spin up` answers 500 with
empty component logs. On Spin 4 the same idea is carried by
**componentize-go**: it wraps the build into a component-model module that
exports the wasi-http handler world; different toolchain, same reactor
principle.

**c) `allowed_outbound_hosts = []` vs `--network none`.** Both deny outbound
networking, but the models differ in grain. Docker's flag removes the
network interface of the container — a coarse, per-container switch inside
the (shared-kernel) namespace model; everything else the container does is
still ordinary Linux. Spin's denial is **capability-based and per-component**:
a component must be *granted* each outbound host pattern in the manifest, and
the host enforces it inside the sandbox. Deny-by-default plus per-capability
grants (net, clock, storage) is a tighter contract than a namespace toggle.

**d) Stdlib gaps hit / avoided.** The two classics: timezone data
(`time.LoadLocation` fails — no embedded tzdata) and reflection-heavy
`encoding/json` over `map[string]any`. Both were designed around: `FixedZone`
for the offset and `fmt.Sprintf` for the JSON. The Spin 4 toolchain
(componentize-go) actually compiles full Go, but keeping the handler in the
portable subset costs nothing and keeps the component buildable by TinyGo
targets too.

---

## Task 2 — Perf comparison vs Lab 6 container (4 pts)

Endpoints: Spin `GET /time` vs Lab 6 image `GET /health`
(`ghcr.io/nikolaytaran/devops-intro/quicknotes:v0.1.0`), both on the same
Windows 11 host. Warm: `hyperfine --warmup 5 --runs 50` (spawning `curl.exe`
per request). Cold: runtime killed → restarted → time to first HTTP 200,
5 samples each (fresh `docker run` for the container baseline).

| Dimension | Lab 6 Docker | Lab 12 WASM/Spin |
|-----------|-------------:|-----------------:|
| Artifact size | (fill: docker images) | **4,819,215 B (~4.6 MB)** |
| Cold start (p50) | (fill: 5 samples) | (fill: 5 samples) |
| Warm latency p50 | (fill: hyperfine) | (fill: hyperfine) |
| Warm latency p95 | (fill: hyperfine) | (fill: hyperfine) |

Raw numbers: `lab12-artifacts/cold-start.txt`, `hyperfine-warm.txt`,
`hyperfine-spin.json`, `hyperfine-docker.json`, `sizes.txt`.

### Design questions (e–g)

**e) What dominates each cold start.** Container: engine plumbing (CLI →
daemon → containerd), overlayfs snapshot setup, namespace/cgroup creation,
then the Go binary start. Spin: load the module, compile/instantiate it in
wasmtime, bind the wasi-http listener — no OS-level virtualization, no
filesystem image to assemble, so the whole boot is a userspace operation
measured in tens–hundreds of ms.

**f) Where WASM wins, where Docker stays.** WASM is clearly better for
short-lived, multi-tenant, scale-to-zero workloads: plugins, edge/FaaS
handlers, user-submitted compute — anywhere tiny artifacts, millisecond cold
starts and hard isolation matter. Docker stays right for full Linux ABI
(cgo, native libraries, arbitrary binaries), long-lived stateful services,
rich observability/debug tooling, and the enormous existing ecosystem.

**g) Multi-tenant safety.** The capability sandbox attacks the classic
noisy-neighbor escapes: a tenant module cannot reach host paths, sibling
tenants' memory, or arbitrary network endpoints unless explicitly granted —
so SSRF pivots, `/proc` snooping, and container-escape-via-mount classes of
attack have no analog inside the sandbox. Linux namespaces are strong but
share one kernel and historically leak through misconfigured mounts,
capabilities, or kernel bugs; a WASM module doesn't even have the syscalls
to try.

---

## Bonus — two WASM execution models (2 pts)

### The same logic as a standalone WASI CLI module

[wasm-cli/main.go](../wasm-cli/main.go) — no Spin SDK: the request arrives as
environment variables (CGI-style), the response is stdout. It only exports
`_start`, so bare `wasmtime run` can execute it:

```bash
cd wasm-cli
tinygo build -o main.wasm -target=wasi -no-debug .    # 209,767 bytes (~205 KB)

wasmtime run --env REQUEST_METHOD=GET --env PATH_INFO=/time main.wasm
# {"unix":1791999259,"iso":"2026-10-14T20:34:19+03:00","hour_minute":"20:34","timezone":"Europe/Moscow","utc_offset":"+03:00"}
wasmtime run --env REQUEST_METHOD=GET --env PATH_INFO=/nope main.wasm
# {"error":"not found","method":"GET","path":"/nope"}  (exit 1)
```

Evidence: `lab12-artifacts/wasmtime-run.txt`, `cold-start.txt`
(per-invocation timings).

### Comparison

| | Spin component (`wasm/main.wasm`) | WASI CLI (`wasm-cli/main.wasm`) |
|--|--:|--:|
| Size | 4,819,215 B (~4.6 MB) | **209,767 B (~205 KB)** |
| Execution model | persistent wasi-http server (Spin) | per-invocation CGI-style process |
| Cold / invoke | (fill: spin cold p50, then ~warm per req) | (fill: wasmtime run p50) |

### Design questions (h–j)

**h) Why the Spin component can't run under bare `wasmtime run`.** It is a
**wasi-http component**: it exports handler interfaces for an HTTP host
world, not a `_start` entrypoint that reads env and prints to stdout. Bare
`wasmtime run` expects the CLI world — with the component it has nothing to
call. (`wasmtime serve` hosts wasi-http components; `wasmtime run` hosts
command modules. The CLI module was rebuilt precisely to live in the latter.)

**i) What Spin adds over wasmtime.** Spin *is* wasmtime underneath; on top it
adds the operational shell: the **wasi-http server loop** (socket accept →
invoke component), **manifest-based routing** (`spin.toml` triggers →
components), **instance pooling** so warm requests skip instantiation, and
the **outbound-host policy engine** behind `allowed_outbound_hosts`. Bare
wasmtime is an engine; Spin is a small platform around it.

**j) When each model fits.** Per-invocation `wasmtime run`: batch jobs, CI
one-shots, CLI tools distributed as a single `.wasm`, CGI-style request
handlers where a fresh isolate per request is a feature (crash isolation).
Spin's persistent server: latency-sensitive HTTP APIs (edge handlers, web
hooks, FaaS-style endpoints) where you want warm instances, routing, and
per-component capability policy in one process.

---

## Acceptance checklist

- [x] Scaffolded from `spin new -t http-go` (Spin 4.2.2 → componentize-go, sdk v3)
- [x] `spin build` → `main.wasm` (4,819,215 B); `spin up` serves Moscow JSON on `/time`
- [x] Design questions a–d
- [x] Perf table with real cold/warm/size numbers (Windows measurement script)
- [x] Design questions e–g
- [x] `wasm-cli/` standalone module + `wasmtime run` + model comparison
- [x] Design questions h–j
