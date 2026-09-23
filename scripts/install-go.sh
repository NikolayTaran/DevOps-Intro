#!/usr/bin/env bash
# Lab 5: install pinned Go toolchain (idempotent)
set -euo pipefail

GO_VERSION="1.24.5"
TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
URL="https://go.dev/dl/${TARBALL}"

# Идемпотентность: если точная версия уже стоит — выходим
if command -v go >/dev/null 2>&1 && go version | grep -q "go${GO_VERSION}"; then
  echo "==> Go ${GO_VERSION} already installed: $(go version). Skipping."
  exit 0
fi

echo "==> Installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends curl ca-certificates git rsync

echo "==> Downloading ${URL}"
curl -fsSL "$URL" -o "/tmp/${TARBALL}"

echo "==> Extracting to /usr/local"
rm -rf /usr/local/go
tar -C /usr/local -xzf "/tmp/${TARBALL}"
rm -f "/tmp/${TARBALL}"

# Симлинки — чтобы `go` был виден в любом shell, включая `vagrant ssh -c`
ln -sf /usr/local/go/bin/go    /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh

echo "==> Installed: $(go version)"