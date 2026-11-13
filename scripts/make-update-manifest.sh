#!/usr/bin/env bash
# Build the Keyward update feed for a release and sign it — the family
# single-file wrapper (payback baseline, shared spec: taskly
# shared/spec/UPDATE.md).
#
# Usage: scripts/make-update-manifest.sh <tag> <dist-dir> <key-der-path>
#   <tag>          release tag, e.g. v0.3.0 (must match the VERSION file,
#                  rivet.rktd, and the CHANGELOG — release jobs run
#                  scripts/check-release-version.sh before packaging)
#   <dist-dir>     directory containing the release artifacts, i.e. the
#                  names the release pipeline produces:
#                    keyward-<version>-macos-arm64.dmg
#                    keyward-<version>-macos-x64.dmg
#                    keyward-<version>-windows-x64.msi
#                    keyward-<version>-linux-x86_64.AppImage
#                    keyward-<version>-linux-aarch64.AppImage
#   <key-der-path> Ed25519 private key in DER (OneAsymmetricKey) form; the
#                  CI secret stores it base64-encoded.
#
# Emits <dist-dir>/update-manifest.json — a single self-contained signed
# wrapper carrying every platform × architecture. No channel-file alias:
# Keyward never shipped an update feed before this key existed, so there
# are no pre-switch clients and the canonical name is the only name.
#
# Feed policy (docs/UPDATE-SECURITY.md "Future product flow" #6): the feed
# carries the install handoffs the updater will drive — macOS app-bundle
# replacement (dmg), Windows MSI upgrade, Linux AppImage replacement.
# DEB/RPM upgrade through the package manager and the portable zips are
# human/package-manager assets, not feed entries.
#
# The signing, artifact hashing, schema validation, and feed format live in
# `raco rivet sign-manifest`; this wrapper owns only Keyward's five
# artifacts, the `app` component, and identity.
#
# Env overrides: RELEASE_ASSET_BASE_URL, RIVET_UPDATE_KEY_ID.
set -euo pipefail

TAG="${1:?usage: make-update-manifest.sh <tag> <dist-dir> <key-der-path>}"
DIST="${2:?usage: make-update-manifest.sh <tag> <dist-dir> <key-der-path>}"
KEY_PATH="${3:?usage: make-update-manifest.sh <tag> <dist-dir> <key-der-path>}"
VERSION="${TAG#v}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$(cd "$DIST" && pwd)"
cd "$ROOT"
KEY_ID="${RIVET_UPDATE_KEY_ID:-keyward-2026-11}"
BASE_URL="${RELEASE_ASSET_BASE_URL:-https://github.com/turlamai/keyward/releases/download/$TAG}"

raco rivet check-release-version "$TAG"

BUILD="$(sed -nE 's/.*\(build \. ([0-9]+)\).*/\1/p' "$ROOT/rivet.rktd" | head -n1)"
[[ -n "$BUILD" ]] || {
  echo "error: could not read build from rivet.rktd" >&2
  exit 1
}
[[ -f "$KEY_PATH" ]] || {
  echo "error: missing signing key $KEY_PATH" >&2
  exit 1
}

raco rivet sign-manifest \
  --application-id site.jrtx.keyward \
  --version "$VERSION" \
  --build "$BUILD" \
  --channel stable \
  --base-url "$BASE_URL" \
  --key-id "$KEY_ID" \
  --private-key "$KEY_PATH" \
  --output "$DIST/update-manifest.json" \
  --artifact "macos:arm64:dmg:$DIST/keyward-$VERSION-macos-arm64.dmg:app" \
  --artifact "macos:x64:dmg:$DIST/keyward-$VERSION-macos-x64.dmg:app" \
  --artifact "windows:x64:msi:$DIST/keyward-$VERSION-windows-x64.msi:app" \
  --artifact "linux:x64:appimage:$DIST/keyward-$VERSION-linux-x86_64.AppImage:app" \
  --artifact "linux:arm64:appimage:$DIST/keyward-$VERSION-linux-aarch64.AppImage:app" \
  --rollback-allowed

echo "manifest: $DIST/update-manifest.json (macos arm64/x64 dmg + windows x64 msi + linux x86_64/aarch64 AppImage)"
