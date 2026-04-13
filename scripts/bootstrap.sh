#!/usr/bin/env bash
set -euo pipefail

echo "[bootstrap] Checking Go toolchain..."
if ! command -v go > /dev/null 2>&1; then
  echo "ERROR: Go is not installed. Install Go 1.21+ from https://go.dev/dl/" >&2
  exit 1
fi

GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
GO_MAJOR=$(echo "$GO_VERSION" | cut -d. -f1)
GO_MINOR=$(echo "$GO_VERSION" | cut -d. -f2)
if [ "$GO_MAJOR" -lt 1 ] || { [ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -lt 21 ]; }; then
  echo "ERROR: Go 1.21+ required, found $GO_VERSION" >&2
  exit 1
fi
echo "[bootstrap] Go $GO_VERSION ✓"

echo "[bootstrap] Checking gomobile..."
if ! command -v gomobile > /dev/null 2>&1; then
  echo "[bootstrap] gomobile not found, installing..."
  go install golang.org/x/mobile/cmd/gomobile@latest
  GOBIN="$(go env GOPATH)/bin"
  export PATH="$GOBIN:$PATH"
  echo "[bootstrap] gomobile installed to $GOBIN"
  echo "[bootstrap] Add $GOBIN to your PATH permanently."
fi

echo "[bootstrap] Running gomobile init (one-time)..."
gomobile init

echo "[bootstrap] ✓ Ready. Next: ./scripts/build-xcframework.sh"
