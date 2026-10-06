package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// newSecuredHandler builds the same handler chain as main.go:
// securityHeaders(server.Routes()). If the middleware is unwired from
// main.go's handler construction or deleted from the codebase, every
// assertion below fails — the fix is genuinely guarded by a test
// (Lab 9, §2.3.4), not just "a comment".
func newSecuredHandler(t *testing.T) http.Handler {
	t.Helper()
	store, err := NewStore("") // in-memory store: no file on disk
	if err != nil {
		t.Fatalf("NewStore: %v", err)
	}
	return securityHeaders(NewServer(store).Routes())
}

// TestSecurityHeadersOnAllRoutes asserts the security headers on every
// registered route AND on the mux-generated 404 — the fix must apply to
// ALL routes, not just /health (Lab 9, §2.3.2).
func TestSecurityHeadersOnAllRoutes(t *testing.T) {
	handler := newSecuredHandler(t)

	routes := []struct{ method, path, body string }{
		{"GET", "/health", ""},
		{"GET", "/metrics", ""},
		{"GET", "/notes", ""},
		{"POST", "/notes", `{"title":"t","body":"b"}`},
		{"GET", "/notes/999", ""},
		{"DELETE", "/notes/999", ""},
		{"GET", "/no-such-route", ""}, // mux-generated 404 — still stamped
	}

	want := map[string]string{
		"Content-Security-Policy":      "default-src 'none'",
		"X-Content-Type-Options":       "nosniff",
		"X-Frame-Options":              "DENY",
		"Cross-Origin-Resource-Policy": "same-origin",
		"Cache-Control":                "no-store",
		"Referrer-Policy":              "no-referrer",
	}

	for _, rt := range routes {
		var req *http.Request
		if rt.body != "" {
			req = httptest.NewRequest(rt.method, rt.path, strings.NewReader(rt.body))
			req.Header.Set("Content-Type", "application/json")
		} else {
			req = httptest.NewRequest(rt.method, rt.path, nil)
		}
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		for k, v := range want {
			if got := rec.Header().Get(k); got != v {
				t.Errorf("%s %s: header %s = %q, want %q (securityHeaders middleware removed?)",
					rt.method, rt.path, k, got, v)
			}
		}
	}
}
