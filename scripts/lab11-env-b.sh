#!/usr/bin/env bash
# Lab 11 — environment B: independent Nix store #2 + a fresh checkout.
# A fresh git clone of the same branch is built with a SEPARATE nix-portable
# store (NP_LOCATION points the whole Nix root at a different directory), so
# nothing can be shared with environment A: no store paths, no caches.
set -euo pipefail

SRC="${SRC:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK="${WORK:-$(mktemp -d)}"
ART="$SRC/submissions/lab11-artifacts"
mkdir -p "$ART"

echo "== [B] fresh clone of $SRC -> $WORK/clone =="
git clone --quiet "$SRC" "$WORK/clone"
cd "$WORK/clone"

export NIX_CONFIG="experimental-features = nix-command flakes"
export NP_LOCATION="$WORK/np-store"
NP="${NP:-nix-portable}"

echo "== [B] nix build .#quicknotes (fresh store) =="
"$NP" nix build .#quicknotes

echo "== [B] store hash =="
"$NP" nix-store --query --hash "$(readlink -f result)" | tee "$ART/hash-env-b.txt"

echo "== [B] nix build .#docker (fresh store) =="
"$NP" nix build .#docker

echo "== [B] sha256sum of the OCI tarball =="
sha256sum "$(readlink -f result)" | tee "$ART/docker-sha-env-b.txt"

echo "== [B] cleanup (fresh clone + its store are throwaway) =="
rm -rf "$WORK"
