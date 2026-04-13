#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUBMODULE="$ROOT/Vendor/tesla-vehicle-command"
PATCH="$ROOT/GoPatches/mobile.go"
OUTPUT="$ROOT/build/TeslaCommand.xcframework"

echo "[build] Ensuring submodule is initialized..."
git -C "$ROOT" submodule update --init --recursive

echo "[build] Injecting mobile.go into submodule..."
mkdir -p "$SUBMODULE/pkg/mobile"
cp "$PATCH" "$SUBMODULE/pkg/mobile/mobile.go"

echo "[build] Ensuring golang.org/x/mobile is in submodule go.mod..."
# gomobile bind compiles golang.org/x/mobile/bind from the target module's context.
# Upstream tesla-vehicle-command does not depend on it, so we add it here.
# This mutates the submodule's go.mod/go.sum at build time; those files are
# inside Vendor/tesla-vehicle-command/ which the outer repo already ignores.
(cd "$SUBMODULE" && go get golang.org/x/mobile@latest >/dev/null 2>&1)

echo "[build] Running gomobile bind (this takes 3–5 min cold)..."
rm -rf "$OUTPUT"
mkdir -p "$ROOT/build"
(cd "$SUBMODULE" && gomobile bind \
  -target=ios,iossimulator \
  -o "$OUTPUT" \
  ./pkg/mobile)

echo "[build] ✓ Built $OUTPUT"
ls -lh "$OUTPUT"
