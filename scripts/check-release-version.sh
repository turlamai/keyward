#!/usr/bin/env bash
# Release preflight: every release identity on this tree must name the same
# version. racket/core/version.rkt is what the carrier, the update-feed
# script and the build read; the root VERSION file and the CHANGELOG entry
# are cross-checked in the same pass so a bump cannot ship half-applied.
# Runs without racket, so CI and every release job can call it before any
# packaging step.
#
#   scripts/check-release-version.sh [tag]     e.g. scripts/check-release-version.sh v0.1.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
TAG="${1:-}"

fail() {
  echo "release preflight: $*" >&2
  exit 1
}

[[ -n "$VERSION" ]] || fail "VERSION is empty"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] || \
  fail "VERSION '$VERSION' is not a supported semantic version"

if [[ -n "$TAG" ]]; then
  TAG_VERSION="${TAG#v}"
  [[ "$TAG_VERSION" == "$VERSION" ]] || \
    fail "tag '$TAG' does not match VERSION '$VERSION'"
fi

CORE_VERSION="$(sed -n 's/^(define app-version "\(.*\)")$/\1/p' "$ROOT/racket/core/version.rkt" | head -1)"
[[ "$CORE_VERSION" == "$VERSION" ]] || \
  fail "racket/core/version.rkt '$CORE_VERSION' does not match VERSION '$VERSION'"

# The glaze carrier must never fall back to a staged Rivet manifest: the
# app metadata is compiled in from version.rkt.
[[ ! -e "$ROOT/rivet.rktd" ]] || \
  fail "rivet.rktd is still present; the glaze carrier reads racket/core/version.rkt"

# The CHANGELOG must carry a dated Keep-a-Changelog section for the release
# ("## [X.Y.Z] - YYYY-MM-DD"), so a bump cannot ship unnamed.
grep -qE "^## \[${VERSION//./\\.}\] - " "$ROOT/CHANGELOG.md" || \
  fail "CHANGELOG.md has no dated '[${VERSION}]' entry"

echo "release preflight: version $VERSION is aligned (VERSION == version.rkt == CHANGELOG)"
