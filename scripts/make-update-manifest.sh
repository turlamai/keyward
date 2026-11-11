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
# wrapper (schema + base64 payload + signature block) carrying every
# platform × architecture. No channel-file alias: Keyward never shipped an
# update feed before this key existed, so there are no pre-switch clients
# and the canonical name is the only name.
#
# Feed policy (docs/UPDATE-SECURITY.md "Future product flow" #6): the feed
# carries the install handoffs the updater will drive — macOS app-bundle
# replacement (dmg), Windows MSI upgrade, Linux AppImage replacement.
# DEB/RPM upgrade through the package manager and the portable zips are
# human/package-manager assets, not feed entries.
#
# Signing happens in the publish job over the merged dist/ (one feed, not
# rivet's per-platform manifests; the release legs stay
# --without-updates). The workflow fails closed without the correct
# signing secret — docs/UPDATE-SECURITY.md release-signing prerequisite.
#
# Env overrides: RELEASE_ASSET_BASE_URL, RIVET_UPDATE_KEY_ID.

set -euo pipefail

TAG="${1:?usage: make-update-manifest.sh <tag> <dist-dir> <key-der-path>}"
DIST="${2:?usage: make-update-manifest.sh <tag> <dist-dir> <key-der-path>}"
KEY_PATH="${3:?usage: make-update-manifest.sh <tag> <dist-dir> <key-der-path>}"
VERSION="${TAG#v}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_ID="${RIVET_UPDATE_KEY_ID:-keyward-2026-11}"
BASE_URL="${RELEASE_ASSET_BASE_URL:-https://github.com/turlamai/keyward/releases/download/$TAG}"

# ---- verify tag/version alignment -------------------------------------------
[[ "$VERSION" == "$(tr -d '[:space:]' < "$ROOT/VERSION")" ]] || {
  echo "error: tag $TAG does not match VERSION '$(cat "$ROOT/VERSION")'" >&2; exit 1; }

for artifact in "$DIST/keyward-$VERSION-macos-arm64.dmg" \
                "$DIST/keyward-$VERSION-macos-x64.dmg" \
                "$DIST/keyward-$VERSION-windows-x64.msi" \
                "$DIST/keyward-$VERSION-linux-x86_64.AppImage" \
                "$DIST/keyward-$VERSION-linux-aarch64.AppImage"; do
  [[ -f "$artifact" ]] || { echo "error: missing $artifact" >&2; exit 1; }
done

# ---- build + sign the merged manifest with rivet's own signer ---------------
MANIFEST="$DIST/update-manifest.json"

SCRIPT="$(mktemp /tmp/keyward-manifest-XXXXXX.rkt)"
trap 'rm -f "$SCRIPT"' EXIT

cat > "$SCRIPT" <<RKT
#lang racket/base
(require rivet/distribution
         racket/date
         racket/file
         racket/format)
(define version "$VERSION")
(define base-url "$BASE_URL")
(define dist (path->complete-path "$DIST"))
(define key-path (path->complete-path "$KEY_PATH"))
(define key-id "$KEY_ID")
(define build (hash-ref (file->value (build-path (path->complete-path "$ROOT") "rivet.rktd")) 'build))

(define (artifact platform architecture file installer)
  (define path (build-path dist file))
  (unless (file-exists? path)
    (error 'make-update-manifest "missing installer: ~a" path))
  ;; rivet's multi-component feed: keyward ships exactly one installable
  ;; per platform × architecture — the component is 'app
  (update-artifact platform architecture
                   (string-append base-url "/" file)
                   (sha256-file/hex path)
                   (file-size path)
                   installer
                   '()
                   'app))

;; Handoff-shaped feed: dmg entries for both macOS architectures, the MSI
;; for Windows, the AppImage entries for Linux. Portable zips, deb/rpm and
;; the flatpak bundles are human/package-manager assets only.
(define manifest
  (update-manifest "site.jrtx.keyward"
                   version
                   build
                   'stable
                   ;; published-at: RFC 3339, second precision, UTC
                   (let ([d (seconds->date (current-seconds) #f)])
                     (format "~a-~a-~aT~a:~a:~aZ"
                             (date-year d)
                             (~r (date-month d) #:min-width 2 #:pad-string "0")
                             (~r (date-day d) #:min-width 2 #:pad-string "0")
                             (~r (date-hour d) #:min-width 2 #:pad-string "0")
                             (~r (date-minute d) #:min-width 2 #:pad-string "0")
                             (~r (date-second d) #:min-width 2 #:pad-string "0")))
                   "0.0.0"
                   #f
                   #t
                   100
                   (list (artifact 'macos 'arm64
                                   (format "keyward-~a-macos-arm64.dmg" version) 'dmg)
                         (artifact 'macos 'x64
                                   (format "keyward-~a-macos-x64.dmg" version) 'dmg)
                         (artifact 'windows 'x64
                                   (format "keyward-~a-windows-x64.msi" version) 'msi)
                         (artifact 'linux 'x64
                                   (format "keyward-~a-linux-x86_64.AppImage" version) 'appimage)
                         (artifact 'linux 'arm64
                                   (format "keyward-~a-linux-aarch64.AppImage" version) 'appimage))))

;; write-signed-manifest validates the struct against the manifest schema
;; before signing, so a malformed manifest fails the release instead of
;; shipping something every client would reject.
(call-with-output-file (build-path dist "update-manifest.json")
  #:exists 'truncate/replace
  (lambda (out)
    (write-signed-manifest manifest
                           (read-ed25519-private-key key-path)
                           key-id
                           out)
    (newline out)))
(printf "manifest: ~a (5 artifacts, key-id ~a)\\n"
        (build-path dist "update-manifest.json") key-id)
RKT

# rivet must be installed for the signer; the publish job links a checkout
racket "$SCRIPT"

echo "manifest: $MANIFEST (macos arm64/x64 dmg + windows x64 msi + linux x86_64/aarch64 AppImage)"
