#!/usr/bin/env bash
# Lab 11 — environment A: independent Nix store #1.
# Uses nix-portable (rootless Nix, single static binary) so the build does not
# depend on a system-wide /nix or a Docker daemon. dockerTools needs no daemon.
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
ART="$REPO/submissions/lab11-artifacts"
mkdir -p "$ART"
cd "$REPO"

export NIX_CONFIG="experimental-features = nix-command flakes"
NP="${NP:-nix-portable}"

echo "== [A] nix build .#quicknotes =="
"$NP" nix build .#quicknotes --print-build-logs 2>&1 | tee "$ART/nix-build-quicknotes.txt"

echo "== [A] store hash (nix-store --query --hash) =="
"$NP" nix-store --query --hash "$(readlink -f result)" | tee "$ART/hash-env-a.txt"

echo "== [A] run the built binary and probe /health =="
ADDR=:18080 DATA_PATH=/tmp/qa-notes.json SEED_PATH="$REPO/app/seed.json" \
  ./result/bin/quicknotes & QN_PID=$!
sleep 1
curl -fsS http://127.0.0.1:18080/health | tee "$ART/health-env-a.txt"
kill "$QN_PID" 2>/dev/null || true

echo "== [A] nix build .#docker (no Docker daemon involved) =="
"$NP" nix build .#docker --print-build-logs 2>&1 | tee "$ART/nix-build-docker.txt"

echo "== [A] sha256sum of the OCI tarball =="
sha256sum "$(readlink -f result)" | tee "$ART/docker-sha-env-a.txt"
ls -lh result
