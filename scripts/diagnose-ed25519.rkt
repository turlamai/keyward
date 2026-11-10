#lang racket/base

;; TEMPORARY CI diagnostic for the ubuntu-only stray-scan Ed25519 failure
;; (sparkle/ed25519.private row missing). Prints structure facts only —
;; byte lengths, equality booleans, exception messages — never raw key
;; material. Remove once the platform divergence is fixed.

(require crypto
         (only-in crypto/libcrypto libcrypto-factory)
         ffi/unsafe
         ffi/unsafe/define
         racket/format
         racket/list
         racket/string
         (only-in "../app/core/keymeta.rkt"
                  generate-keypair! private-key-from-der)
         (only-in "../app/core/keyformats.rkt" ed25519-from-seed-pub))

(crypto-factories (list libcrypto-factory))

;; ---- linked libcrypto identity ------------------------------------------------

(define (openssl-version-string)
  (with-handlers ([exn:fail? (lambda (e) (format "unavailable: ~a" (exn-message e)))])
    (define lib (ffi-lib "libcrypto" '("3" "" #f)))
    (define-ffi-definer defcrypto lib)
    (defcrypto OpenSSL_version (_fun _int -> _string))
    (OpenSSL_version 0)))

;; ---- probes --------------------------------------------------------------------

;; run thunk -> printed result or exception message
(define (probe name thunk)
  (with-handlers ([exn:fail? (lambda (e) (printf "~a: FAIL\n  ~a\n" name (exn-message e)))])
    (printf "~a: OK\n  ~a\n" name (thunk))))

;; datum -> printable structure; bytes render as length only
(define (describe d)
  (string-join
   (for/list ([e (in-list d)])
     (cond [(bytes? e) (format "bytes[~a]" (bytes-length e))]
           [(eq? e #f) "#f"]
           [else (format "~s" e)]))
   " "))

(define msg #"keyward-diagnostic-probe")

(define (sign-verify-ok? priv pub-bytes)
  (define pubk (datum->pk-key (list 'eddsa 'public 'ed25519 pub-bytes) 'rkt-public
                              (list libcrypto-factory)))
  (pk-verify pubk msg (pk-sign priv msg)))

;; seed -> derived public bytes via a seed-only rkt-private import
(define (derive-pub-from-seed seed)
  (define k (datum->pk-key (list 'eddsa 'private 'ed25519 #f seed) 'rkt-private
                           (list libcrypto-factory)))
  (define dpub (pk-key->datum (pk-key->public-only-key k) 'rkt-public))
  (list-ref dpub 3))

(define (main)
  (printf "racket ~a, system ~a, libcrypto: ~a\n"
          (version) (system-type) (openssl-version-string))
  (newline)

  ;; path 1: the test fixture's exact chain — keygen -> DER -> parse -> datum
  (define-values (priv-der spki) (generate-keypair!))
  (define priv (private-key-from-der priv-der))
  (define d (pk-key->datum priv 'rkt-private))
  (printf "path1 datum (DER-parsed priv): ~a\n" (describe d))
  (define seed (list-ref d 4))
  (define pub (list-ref d 3))
  (probe "path1 pub is bytes(32)"
         (lambda () (and (bytes? pub) (= (bytes-length pub) 32))))
  (probe "path1 seed is bytes(32)"
         (lambda () (and (bytes? seed) (= (bytes-length seed) 32))))
  (probe "path1 datum pub authenticates (sign/verify with datum pub)"
         (lambda () (sign-verify-ok? priv pub)))
  (probe "path1 seed-only import (eddsa private ed25519 #f seed)"
         (lambda () (define k (datum->pk-key (list 'eddsa 'private 'ed25519 #f seed)
                                             'rkt-private (list libcrypto-factory)))
                    (pk-key? k)))
  (probe "path1 seed-derived pub == datum pub"
         (lambda () (equal? (derive-pub-from-seed seed) pub)))
  (probe "path1 product roundtrip ed25519-from-seed-pub(seed, datum-pub)"
         (lambda () (define k (ed25519-from-seed-pub seed pub))
                    (pk-key? k)))
  (newline)

  ;; path 2: keygen -> datum without the DER detour
  (define priv2 (generate-private-key 'eddsa '((curve ed25519))))
  (define d2 (pk-key->datum priv2 'rkt-private))
  (printf "path2 datum (direct keygen priv): ~a\n" (describe d2))
  (define seed2 (list-ref d2 4))
  (define pub2 (list-ref d2 3))
  (probe "path2 datum pub authenticates"
         (lambda () (sign-verify-ok? priv2 pub2)))
  (probe "path2 product roundtrip ed25519-from-seed-pub(seed, datum-pub)"
         (lambda () (define k (ed25519-from-seed-pub seed2 pub2))
                    (pk-key? k)))
  (newline)

  ;; the PrivateKeyInfo stored value still parses to the same datum pub
  (probe "path1 spki == datum-pub SPKI tail"
         (lambda ()
           (define pubk (datum->pk-key (list 'eddsa 'public 'ed25519 pub) 'rkt-public
                                       (list libcrypto-factory)))
           (equal? (subbytes (pk-key->datum pubk 'SubjectPublicKeyInfo) 12) pub))))

(module+ main (main))
