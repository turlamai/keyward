#lang racket/base

;; Wire-level regression tests for the update-check row contract. Synthetic
;; signing keys exist only in memory; the pinned trust root is injected as a
;; keyword so these tests exercise the full verify→select→row path without
;; the release signing material. No network contact, no real vault, no
;; stored secret, and no installed binary is touched.

(require crypto
         crypto/all
         rackunit
         racket/string
         rivet/distribution
         "../racket/backend.rkt"
         "../racket/update-policy.rkt")

(use-all-factories!)

(define private-key (generate-private-key 'eddsa '((curve ed25519))))
(define trusted-public-key
  (datum->pk-key (pk-key->datum private-key 'rkt-public) 'rkt-public))
(define another-key (generate-private-key 'eddsa '((curve ed25519))))
(define key-id "keyward-test-2026")
(define asset-url
  "https://github.com/turlamai/keyward/releases/download/v0.4.0/keyward-0.4.0-windows-x64.msi")
(define artifact
  (update-artifact 'windows 'x64 asset-url (make-string 64 #\a)
                   4096 'msi '() #f))
(define release
  (update-manifest keyward-update-application-id "0.4.0" 1
                   'stable "2026-11-01T00:00:00Z" "0.0.0" #f
                   #t 100 (list artifact)))

(define (signed-by manifest key [id key-id])
  (define out (open-output-bytes))
  (write-signed-manifest manifest key id out)
  (get-output-bytes out))

(define (review signed-bytes
                #:pub [pub trusted-public-key]
                #:id [id key-id]
                #:version [version "0.3.0"]
                #:channel [channel "stable"]
                #:install-kind [install-kind "msi"]
                #:linux-format [linux-format ""]
                #:platform [platform 'windows]
                #:architecture [architecture 'x64])
  (update-check-review signed-bytes install-kind linux-format
                       #:trusted-public-key pub
                       #:expected-key-id id
                       #:current-version version
                       #:release-channel channel
                       #:platform platform
                       #:architecture architecture))

(define (status-of row) (list-ref row 0))
(define (detail-of row) (list-ref row 7))

;; A valid signed newer release comes back as one fully populated row —
;; signed metadata only, ordered (status version installer size name url
;; published detail).
(check-equal?
 (review (signed-by release private-key))
 (list "available" "0.4.0" "msi" "4096"
       "keyward-0.4.0-windows-x64.msi" asset-url
       "2026-11-01T00:00:00Z" ""))

;; Signed metadata cannot trigger a reinstall or a downgrade.
(check-equal? (status-of (review (signed-by release private-key)
                                 #:version "0.4.0"))
              "up-to-date")
(check-equal? (status-of (review (signed-by release private-key)
                                 #:version "0.5.0"))
              "up-to-date")

;; A channel the client does not follow is not an available update.
(check-equal? (status-of
               (review (signed-by
                        (struct-copy update-manifest release [channel 'beta])
                        private-key)))
              "up-to-date")
(check-equal? (status-of
               (review (signed-by
                        (struct-copy update-manifest release [channel 'beta])
                        private-key)
                       #:channel "beta"))
              "available")

;; An install kind without a matching signed artifact is up-to-date, not
;; an error: the feed verified, nothing applies to this install shape.
(check-equal? (status-of (review (signed-by release private-key)
                                 #:install-kind "portable"))
              "up-to-date")

;; Forged signatures, wrong key ids, foreign applications and unsigned
;; blobs are typed rejections with a bounded one-line reason — never an
;; Error frame and never a crash.
(check-equal? (status-of (review (signed-by release another-key)))
              "rejected")
(check-true (string-contains? (detail-of (review (signed-by release another-key)))
                              "signature verification failed"))
(check-true (string-contains? (detail-of (review (signed-by release private-key "other-id")))
                              "unexpected key"))
(check-true (string-contains?
             (detail-of
              (review (signed-by
                       (struct-copy update-manifest release
                                    [application-id "site.jrtx.other"])
                       private-key)))
             "application identity mismatch"))
(check-equal? (status-of (review #"not a manifest at all"))
              "rejected")

;; The publisher cannot stage a mutable latest URL, another account's
;; artifact, or a path-traversal asset even when correctly signed.
(for ([bad-url
       (in-list
        (list
         "https://github.com/turlamai/keyward/releases/latest/download/keyward.msi"
         "https://github.com/other/keyward/releases/download/v0.4.0/keyward.msi"
         "https://github.com/turlamai/keyward/releases/download/v0.4.0/../secret"
         "https://github.com/turlamai/keyward/releases/download/v0.4.0/app.msi?raw=1"))])
  (define row
    (review (signed-by
             (struct-copy update-manifest release
                          [artifacts
                           (list (struct-copy update-artifact artifact
                                              [url bad-url]))])
             private-key)))
  (check-equal? (status-of row) "rejected")
  (check-true (string-contains? (detail-of row)
                                "official immutable release tag"))
  (check-false (string-contains? (detail-of row) "\n")))

;; Signed size lies and oversized metadata are rejections too.
(check-equal? (status-of
               (review (signed-by
                        (struct-copy update-manifest release
                                     [artifacts
                                      (list (struct-copy update-artifact artifact
                                                         [size (add1 keyward-update-maximum-bytes)]))])
                        private-key)))
              "rejected")
(check-equal? (status-of
               (review (make-bytes (add1 keyward-update-maximum-manifest-bytes) 65)))
              "rejected")

;; An explicit package-manager format is mandatory on Linux, and the
;; declared format — never feed order — picks the payload.
(define linux-deb
  (update-artifact 'linux 'x64
                   "https://github.com/turlamai/keyward/releases/download/v0.4.0/keyward-0.4.0-linux-amd64.deb"
                   (make-string 64 #\b) 4096 'deb '() #f))
(define linux-rpm
  (update-artifact 'linux 'x64
                   "https://github.com/turlamai/keyward/releases/download/v0.4.0/keyward-0.4.0-linux-x86_64.rpm"
                   (make-string 64 #\c) 4096 'rpm '() #f))
(define linux-release
  (struct-copy update-manifest release [artifacts (list linux-rpm linux-deb)]))
(define linux-signed (signed-by linux-release private-key))
(check-true (string-contains?
             (detail-of (review linux-signed
                                #:install-kind "package-manager"
                                #:platform 'linux))
             "declared deb or rpm format"))
(check-equal?
 (review linux-signed #:install-kind "package-manager" #:linux-format "deb"
         #:platform 'linux)
 (list "available" "0.4.0" "deb" "4096"
       "keyward-0.4.0-linux-amd64.deb"
       "https://github.com/turlamai/keyward/releases/download/v0.4.0/keyward-0.4.0-linux-amd64.deb"
       "2026-11-01T00:00:00Z" ""))
(check-equal? (list-ref (review linux-signed
                                #:install-kind "package-manager"
                                #:linux-format "rpm"
                                #:platform 'linux)
                        4)
              "keyward-0.4.0-linux-x86_64.rpm")

(displayln "Keyward update-check wire contract passed")
