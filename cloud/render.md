# Option A — Render: attempted, blocked by the card wall

**Date:** 2026-10-07 · **Plan:** Free · **Region:** Oregon (US West) · **Source:** existing image (no build)

## What was attempted

Render "New Web Service" → "Deploy an existing image", form filled exactly per Option A:

| Field | Value |
|---|---|
| Image URL | `ghcr.io/nikolaytaran/devops-intro/quicknotes:v0.1.0` (public since Task 1) |
| Region | Oregon (US West) |
| Instance type | Free |
| Env vars | `ADDR=:8080`, `PORT=8080` |
| Advanced | defaults |

The public image reference was accepted, but the **final creation step required adding a credit/debit card** for account verification — including for the Free instance type.

## Why not completed

- Card verification is mandatory before the service is created; no card → no deploy.
- Russian-issued cards are rejected by the payment processor (known course-wide issue; the lab's pinned update explicitly allows switching to **Option B — GitHub Codespaces** when Render demands a card).

## Decision

Proceed with **Option B (GitHub Codespaces)** — see `cloud/codespaces.md`.
The release workflow still carries the optional Render deploy-hook step
(`RENDER_DEPLOY_HOOK` secret): when the secret is unset the step exits 0 and
the release succeeds, so switching options required no workflow changes.
This file is kept as evidence of the Option A attempt.
