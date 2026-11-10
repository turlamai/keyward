#!/usr/bin/env bash
# Release preflight: every release identity on this tree must name the same
# version (taskly-family gate). The root VERSION file is the bump target;
# rivet.rktd and the CHANGELOG entry are cross-checked in the same pass so a
# bump cannot ship half-applied. Runs without racket, so CI and every
# release job can call it before any packaging step.
#
#   scripts/check-release-version.sh [tag]     e.g. scripts/check-release-version.sh v0.3.0
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

# The Rivet app manifest carries the product version on this tree. The first
# dotted number in the file is the version field (min-version fields come
# later and never match the three-segment pattern with this shape).
RIVET_RKTD_VERSION="$(grep -o '"[0-9]*\.[0-9]*\.[0-9]*"' "$ROOT/rivet.rktd" | head -n1 | tr -d '"')"
[[ "$RIVET_RKTD_VERSION" == "$VERSION" ]] || \
  fail "rivet.rktd version '$RIVET_RKTD_VERSION' does not match VERSION '$VERSION'"

# The CHANGELOG must carry a dated Keep-a-Changelog section for the release
# ("## [X.Y.Z] - YYYY-MM-DD"), so a bump cannot ship unnamed.
grep -qE "^## \[${VERSION//./\\.}\] - " "$ROOT/CHANGELOG.md" || \
  fail "CHANGELOG.md has no dated '[${VERSION}]' entry"

echo "release preflight: version $VERSION is aligned (VERSION == rivet.rktd == CHANGELOG)"
