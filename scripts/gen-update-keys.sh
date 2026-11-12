#!/bin/sh
# Generate the Ed25519 update-signing keypair for Keyward.
#
# macOS system LibreSSL lacks Ed25519, so generation goes through Racket's
# crypto package — the same library the updater policy verifies with, which
# also proves the DER round-trips through rivet's own readers.
#
# Usage: scripts/gen-update-keys.sh [output-dir]
#
# The private key signs release update feeds (scripts/make-update-manifest.sh,
# via the UPDATE_ED25519_PRIVATE_KEY_B64 CI secret). It never enters the
# repository: keys/ is gitignored except for the public half. Back the
# private key up outside the checkout (synced key vault + CI secret), and
# rotate via key_id as described in docs/UPDATE-SECURITY.md.

set -eu

OUT_DIR="${1:-keys}"
mkdir -p "$OUT_DIR"

if [ -f "$OUT_DIR/update-ed25519-private.der" ]; then
  echo "gen-update-keys: $OUT_DIR/update-ed25519-private.der already exists" >&2
  exit 1
fi

SCRIPT="$(mktemp /tmp/keyward-gen-keys-XXXXXX.rkt)"
trap 'rm -f "$SCRIPT"' EXIT

cat > "$SCRIPT" <<'RKT'
#lang racket/base
(require crypto
         crypto/all
         rivet/distribution)
(use-all-factories!)
(define out-dir (vector-ref (current-command-line-arguments) 0))
(define priv (generate-private-key 'eddsa '((curve ed25519))))
(define priv-der (pk-key->datum priv 'OneAsymmetricKey))
;; Derive the public half through the library instead of picking datum
;; elements: the rkt-private datum orders (vk sk) for DER-imported keys but
;; (sk vk) for freshly generated ones. rkt-public is always the true vk.
(define pub (datum->pk-key (pk-key->datum priv 'rkt-public) 'rkt-public))
(define pub-der (pk-key->datum pub 'SubjectPublicKeyInfo))
(call-with-output-file (build-path out-dir "update-ed25519-private.der")
  (lambda (o) (write-bytes priv-der o)) #:exists 'truncate/replace)
(call-with-output-file (build-path out-dir "update-ed25519-public.der")
  (lambda (o) (write-bytes pub-der o)) #:exists 'truncate/replace)
(displayln "keypair written")
RKT

racket "$SCRIPT" "$OUT_DIR"
echo "private: $OUT_DIR/update-ed25519-private.der (back this up outside the checkout)"
echo "public:  $OUT_DIR/update-ed25519-public.der"
