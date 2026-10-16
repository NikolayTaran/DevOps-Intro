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
