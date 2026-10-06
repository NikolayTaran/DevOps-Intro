package main

// TEMPORARY: Lab 9 demo file (fs-scan triage + bonus B.2.5).
// Pins golang.org/x/net@v0.30.0, affected by GO-2024-3333 /
// CVE-2024-45338 (unbounded loop in html.Parse, fixed in v0.33.0).
// html.Parse is actually called so govulncheck reports the vuln as
// reachable from the call graph. Reverted after the demo.

import (
    "strings"

    "golang.org/x/net/html"
)

func countLinks(fragment string) (int, error) {
    doc, err := html.Parse(strings.NewReader(fragment))
    if err != nil {
        return 0, err
    }
    count := 0
    var walk func(*html.Node)
    walk = func(n *html.Node) {
        if n.Type == html.ElementNode && n.Data == "a" {
            count++
        }
        for c := n.FirstChild; c != nil; c = c.NextSibling {
            walk(c)
        }
    }
    walk(doc)
    return count, nil
}
