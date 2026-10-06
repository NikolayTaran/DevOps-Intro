package main

import "net/http"

// securityHeaders is the middleware that stamps EVERY response with the
// static security headers ZAP expects from a pure JSON API (Lab 9, §2.3).
//
// One wrapper around the whole router — wired in main.go as
// Handler: securityHeaders(server.Routes()) — instead of Header().Set
// calls sprinkled across handlers, so no route (including mux-generated
// 404/405 responses) can ever ship without them.
func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		// An API serves no scripts/styles/images — the strictest possible
		// CSP: nothing may load from anywhere (ZAP 10038-class finding).
		h.Set("Content-Security-Policy", "default-src 'none'")
		// Stop browsers MIME-sniffing responses away from the declared
		// Content-Type (ZAP 10021: X-Content-Type-Options Header Missing).
		h.Set("X-Content-Type-Options", "nosniff")
		// The API is never a frame target (ZAP 10020-class finding).
		h.Set("X-Frame-Options", "DENY")
		// Same-origin API: responses are not embeddable cross-origin —
		// site-isolation hardening (ZAP 90004 finding).
		h.Set("Cross-Origin-Resource-Policy", "same-origin")
		// Note payloads are per-user state, never cacheable
		// (ZAP 10049: Storable and Cacheable Content).
		h.Set("Cache-Control", "no-store")
		// Mozilla web-security guideline: don't leak referring URLs.
		h.Set("Referrer-Policy", "no-referrer")
		next.ServeHTTP(w, r)
	})
}
