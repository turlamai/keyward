#lang racket/base

;; Offline Keyward update trust/policy regression tests. Synthetic signing
;; keys exist only in memory; these tests do not contact GitHub or touch a
;; real key vault, stored secret, installed binary, or release credentials.

(require crypto
         crypto/all
         rackunit
         rivet/distribution
         "../app/update-policy.rkt")

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
                   4096 'msi '() 'app))
(define release
  (update-manifest keyward-update-application-id "0.4.0" 1
                   'stable "2026-11-01T00:00:00Z" "0.0.0" #f
                   #t 100 (list artifact)))

(define (signed-by manifest key [id key-id])
  (define out (open-output-bytes))
  (write-signed-manifest manifest key id out)
  (get-output-bytes out))

(define signed (signed-by release private-key))
(define (preview signed-bytes
                 #:consent? [consent? #t]
                 #:pub [pub trusted-public-key]
                 #:id [id key-id]
                 #:version [version "0.3.0"]
                 #:install-kind [install-kind 'msi])
  (preview-keyward-update
   signed-bytes
   #:user-initiated? consent?
   #:trusted-public-key pub
   #:expected-key-id id
   #:current-version version
   #:install-kind install-kind
   #:platform 'windows
   #:architecture 'x64))

;; The first gate is user intent, before parsing or verifying any bytes.
(check-exn #rx"explicit user action"
           (lambda () (preview signed #:consent? #f)))
(check-exn #rx"pinned, non-empty"
           (lambda () (preview signed #:id "")))
(check-exn #rx"metadata size limit"
           (lambda ()
             (preview (make-bytes
                       (add1 keyward-update-maximum-manifest-bytes)
                       65))))
(check-exn #rx"explicit supported installation kind"
           (lambda () (preview signed #:install-kind #f)))
(define candidate (preview signed))
(check-true (update-candidate? candidate))
(check-equal? (update-artifact-installer
               (update-candidate-artifact candidate))
              'msi)

;; Signed metadata cannot trigger unnecessary reinstall, downgrade, or
;; the wrong install kind.
(check-false (preview signed #:version "0.4.0"))
(check-false (preview signed #:version "0.5.0"))
(check-false (preview signed #:install-kind 'portable))

;; The same key ID is insufficient if the Ed25519 signature is invalid.
(check-exn #rx"signature verification failed"
           (lambda () (preview (signed-by release another-key))))
(check-exn #rx"unexpected key"
           (lambda ()
             (preview (signed-by release private-key "other-id"))))
(check-exn #rx"update manifest application identity mismatch"
           (lambda ()
             (preview (signed-by
                       (struct-copy update-manifest release
                                    [application-id "site.jrtx.other"])
                       private-key))))

;; The publisher cannot accidentally stage a mutable latest URL, another
;; account's artifact, or a path-traversal asset even when correctly signed.
(for ([bad-url
       (in-list
        (list
         "https://github.com/turlamai/keyward/releases/latest/download/keyward.msi"
         "https://github.com/other/keyward/releases/download/v0.4.0/keyward.msi"
         "https://github.com/turlamai/keyward/releases/download/v0.4.0/../secret"
         "https://github.com/turlamai/keyward/releases/download/v0.4.0/app.msi?raw=1"))])
  (check-exn #rx"official immutable release tag"
             (lambda ()
               (preview
                (signed-by
                 (struct-copy update-manifest release
                              [artifacts
                               (list (struct-copy update-artifact artifact
                                                  [url bad-url]))])
                 private-key)))))

(check-exn #rx"exceeds maximum permitted download size"
           (lambda ()
             (preview
              (signed-by
               (struct-copy update-manifest release
                            [artifacts
                             (list (struct-copy update-artifact artifact
                                                [size (add1 keyward-update-maximum-bytes)]))])
               private-key))))

(displayln "Keyward offline update trust policy passed")
