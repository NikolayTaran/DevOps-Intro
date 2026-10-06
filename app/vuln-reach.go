package main

// TEMPORARY (bonus B.2.5): makes countLinks — and with it html.Parse from
// golang.org/x/net@v0.30.0 — reachable from an entry point (init), so
// govulncheck reports GO-2024-3333 / CVE-2024-45338 as affecting this code.
// Removed by the fix commit right after the red run.

func init() { _, _ = countLinks("<a></a>") }