#lang racket/base

;; Stray-key scanner tests — fixture trees in a scratch directory; rows
;; carry path/line/kind/fingerprint only.

(require net/base64
         rackunit
         racket/file
         racket/list
         racket/path
         racket/string
         (only-in crypto pk-key->datum datum->pk-key)
         (only-in crypto/libcrypto libcrypto-factory)
         "../racket/core/keyformats.rkt"
         "../racket/core/keymeta.rkt"
         "../racket/core/strayscan.rkt")

(define (b64 btes) (bytes->string/utf-8 (base64-encode btes "")))

(define-values (priv-der spki) (generate-keypair!))
(define priv (private-key-from-der priv-der))
(define expected-fp (fingerprint-of-der spki))
(define priv-datum (pk-key->datum priv 'rkt-private))
(define seed (list-ref priv-datum 4))
(define pub (list-ref priv-datum 3))

(define (make-tree!)
  (define root (make-temporary-file "keyward-scan~a" 'directory))
  (define (put rel content)
    (define p (build-path root rel))
    (make-directory* (path-only p))
    (with-output-to-file p (lambda () (display content)) #:exists 'replace))
  ;; a PEM private key on line 3 of a readme
  (put "notes/readme.md"
       (string-append "# scratch\n\n"
                      "-----BEGIN PRIVATE KEY-----\n"
                      (b64 priv-der) "\n"
                      "-----END PRIVATE KEY-----\n"))
  ;; a single-line base64(DER) key with a key-ish extension
  (put "deploy/server.key" (b64 priv-der))
  ;; a Sparkle-style base64(seed||pub) file
  (put "sparkle/ed25519.private" (b64 (bytes-append seed pub)))
  ;; public material alone is never flagged
  (put "public/pub.pem"
       (string-append "-----BEGIN PUBLIC KEY-----\n"
                      (b64 spki) "\n"
                      "-----END PUBLIC KEY-----\n"))
  ;; plain files are invisible to the scan
  (put "src/main.rs" "fn main() { println!(\"hello\"); }")
  ;; vendored trees are skipped
  (put "node_modules/left-pad/index.js" "// pem-like: -----BEGIN PRIVATE KEY-----")
  ;; binary files are skipped
  (put "assets/logo.bin" (bytes-append (make-bytes 100 65) #"\0" (make-bytes 100 66)))
  root)

(define root (make-tree!))

(define rows (stray-scan root '()))

;; exactly the three private-key strays, stable order
(check-equal? (length rows) 3)
(define paths (map car rows))
(check-not-false (member "notes/readme.md" paths))
(check-not-false (member "deploy/server.key" paths))
(check-not-false (member "sparkle/ed25519.private" paths))

;; the PEM hit reports its 1-based line and kind label
(define pem-row (car (filter (lambda (r) (string=? (car r) "notes/readme.md")) rows)))
(check-equal? (cadr pem-row) "3")
(check-true (string-prefix? (list-ref pem-row 2) "pem-private("))
(check-equal? (list-ref pem-row 3) expected-fp)

;; the base64(DER) and Sparkle hits carry fingerprints, never values
(define key-row (car (filter (lambda (r) (string=? (car r) "deploy/server.key")) rows)))
(check-equal? (list-ref key-row 2) "der-private")
(check-equal? (list-ref key-row 3) expected-fp)

(define sparkle-row (car (filter (lambda (r) (string=? (car r) "sparkle/ed25519.private")) rows)))
(check-equal? (list-ref sparkle-row 2) "sparkle-style-private")
(check-equal? (list-ref sparkle-row 3) expected-fp)

;; rows never carry key material: every field is short and safe — and the
;; wire contract is (List (List String)), so every field must be a string
(for* ([row (in-list rows)] [field (in-list row)])
  (check-true (string? field))
  (check-true (< (string-length field) 120)))

;; the vault file itself and the snapshot history are excluded
(define vault (build-path root "vaults/secrets.ini"))
(make-directory* (path-only vault))
(with-output-to-file vault
  (lambda () (display (string-append "[p]\nUPDATE_ED25519_PRIVATE_KEY_B64 = " (b64 priv-der) "\n")))
  #:exists 'replace)
(define excl-rows (stray-scan root (list vault (build-path root "vaults/.history/keyward"))))
(check-false (member "vaults/secrets.ini" (map car excl-rows)))

;; nonexistent root raises
(check-exn exn:fail? (lambda () (stray-scan (build-path root "nope") '())))

;; regression: a Sparkle file whose base64 text begins with "0" — the
;; seed's first byte in #xD0-#xD3 — must still be detected. The old
;; first-byte DER sniff misrouted exactly this roll (4/256 per generated
;; key) into the binary-DER branch, where the failed parse swallowed the
;; row with no fallback left.
(define zero-leading-tree
  (let ()
    (define root (make-temporary-file "keyward-scan-zero~a" 'directory))
    (define seed (bytes-append (bytes #xD0) (make-bytes 31 1)))
    (define priv (datum->pk-key (list 'eddsa 'private 'ed25519 #f seed)
                                'rkt-private (list libcrypto-factory)))
    (define pub (list-ref (pk-key->datum priv 'rkt-private) 3))
    (define text (b64 (bytes-append seed pub)))
    ;; the precondition under test: base64 of seed||pub starts with "0"
    (check-equal? (string-ref text 0) #\0)
    (define p (build-path root "k/a.private"))
    (make-directory* (path-only p))
    (with-output-to-file p
      (lambda () (display text))
      #:exists 'replace)
    root))
(define zero-rows (stray-scan zero-leading-tree '()))
(check-equal? (length zero-rows) 1)
(check-equal? (car (car zero-rows)) "k/a.private")
(check-equal? (list-ref (car zero-rows) 2) "sparkle-style-private")
