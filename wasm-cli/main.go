package main

import (
	"fmt"
	"os"
	"time"
)

// Standalone WASI CLI module (CGI-style): the request arrives through
// environment variables, the "response" is written to stdout. No Spin SDK —
// the module only exports _start, so bare `wasmtime run` can execute it.
func main() {
	method := os.Getenv("REQUEST_METHOD")
	path := os.Getenv("PATH_INFO")
	if method == "" {
		method = "GET"
	}
	if path == "" {
		path = "/time"
	}

	if method != "GET" || path != "/time" {
		fmt.Printf(`{"error":"not found","method":%q,"path":%q}`+"\n", method, path)
		os.Exit(1)
	}

	// Same Moscow logic as the Spin component: FixedZone instead of tzdata,
	// Sprintf-built JSON instead of reflection-heavy encoding/json.
	moscow := time.Now().In(time.FixedZone("Europe/Moscow", 3*60*60))
	fmt.Printf(
		`{"unix":%d,"iso":%q,"hour_minute":%q,"timezone":"Europe/Moscow","utc_offset":"+03:00"}`+"\n",
		moscow.Unix(),
		moscow.Format(time.RFC3339),
		moscow.Format("15:04"),
	)
}
