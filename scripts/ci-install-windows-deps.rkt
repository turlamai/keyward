#lang racket/base
;; GitHub-hosted Windows Racket 9.3 sometimes fails while enumerating its
;; win32-store ROOT certificates (X509*->C receives #f). Use the CA bundle
;; bundled with the runner's Node.js Mozilla roots, without disabling TLS/hostname validation.
;; This must run in the SAME Racket process as the package downloads.
;; (Same recipe as podlens#63 / booklight#75; env var name is per-product.)
(require openssl
         pkg
         racket/file)

(define bundle (getenv "KEYWARD_CI_CA_BUNDLE"))
(unless (and bundle
             (file-exists? bundle)
             (regexp-match? #rx#"-----BEGIN CERTIFICATE-----"
                            (file->bytes bundle)))
  (error 'ci-install-windows-deps
         "trusted Mozilla PEM CA bundle is missing or invalid"))

(ssl-default-verify-sources (list bundle))

(define keel-pin "e11aa621df48daaa319b17ec742ffce808274c81")
(define rivet-pin (or (getenv "RIVET_PIN") "v0.16.0"))
(define glaze-pin (getenv "GLAZE_PIN"))
(unless (and glaze-pin (not (equal? glaze-pin "")))
  (error 'ci-install-windows-deps "GLAZE_PIN is missing"))

;; The patched Keel must be installed first while the package catalog lags;
;; then the rivet revision glaze itself is built against, then glaze.
(pkg-install-command #:auto #t #:no-docs #t
                     (format "https://github.com/turlamai/keel.git#~a" keel-pin))
(pkg-install-command #:auto #t #:no-docs #t
                     (format "https://github.com/turlamai/rivet.git#~a" rivet-pin))
(pkg-install-command #:auto #t #:no-docs #t
                     (format "https://github.com/turlamai/glaze.git#~a" glaze-pin))
;; crypto backs keyward's Ed25519 key work (same package the catalog jobs install).
(pkg-install-command #:auto #t #:no-docs #t "crypto")
