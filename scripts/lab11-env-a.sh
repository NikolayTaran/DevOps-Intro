#!/usr/bin/env bash
# Lab 11 — environment A: independent Nix store #1.
# Uses nix-portable (rootless Nix, single static binary) so the build does not
# depend on a system-wide /nix or a Docker daemon. dockerTools needs no daemon.
#
# NOTE: nix-portable runs Nix inside its own mount namespace: the /nix/store
# paths it prints (and the `result` symlink target) exist only INSIDE that
# namespace. Whatever must see those files on the host — running the binary,
# checksumming the tarball — is materialised with `nix store cat` first.
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
ART="$REPO/submissions/lab11-artifacts"
mkdir -p "$ART"
cd "$REPO"

export NIX_CONFIG="experimental-features = nix-command flakes"
NP="${NP:-nix-portable}"

echo "== [A] nix build .#quicknotes =="
"$NP" nix build .#quicknotes --print-build-logs 2>&1 | tee "$ART/nix-build-quicknotes.txt"
OUT="$("$NP" nix path-info .#quicknotes)"

echo "== [A] store hash (nix-store --query --hash) =="
"$NP" nix-store --query --hash "$OUT" | tee "$ART/hash-env-a.txt"

echo "== [A] run the built binary and probe /health =="
"$NP" nix store cat "$OUT/bin/quicknotes" > "$ART/quicknotes-binary"
chmod +x "$ART/quicknotes-binary"
ADDR=:18080 DATA_PATH=/tmp/qa-notes.json SEED_PATH="$REPO/app/seed.json" \
  "$ART/quicknotes-binary" & QN_PID=$!
sleep 1
curl -fsS http://127.0.0.1:18080/health | tee "$ART/health-env-a.txt"
kill "$QN_PID" 2>/dev/null || true

echo "== [A] nix build .#docker (no Docker daemon involved) =="
"$NP" nix build .#docker --print-build-logs 2>&1 | tee "$ART/nix-build-docker.txt"
IMG="$("$NP" nix path-info .#docker)"

echo "== [A] sha256sum of the OCI tarball =="
"$NP" nix store cat "$IMG" > "$ART/quicknotes-lab11.tar.gz"
sha256sum "$ART/quicknotes-lab11.tar.gz" | tee "$ART/docker-sha-env-a.txt"
ls -lh "$ART/quicknotes-lab11.tar.gz"
