#lang racket/base

;; Keyward handles signing secrets, so updates must not silently contact a
;; server or modify an installed vault. This is deliberately a pure/offline
;; policy and trust boundary, not a network updater or installation handler.
;; The future explicit "Check for updates" UI provides the manifest bytes
;; only after user consent; its trusted public key/key ID must be embedded in
;; the *application build*, never read from the feed being verified.

(require racket/port
         racket/string
         rivet/distribution)

(provide keyward-update-application-id
         keyward-update-maximum-bytes
         keyward-update-maximum-manifest-bytes
         preview-keyward-update)

(define keyward-update-application-id "site.jrtx.keyward")
;; Bound total update payload size *before* any download; Rivet also enforces
;; the exact authenticated size while downloading.
(define keyward-update-maximum-bytes (* 512 1024 1024))
;; The signed wrapper contains metadata only. Reject giant payloads before
;; the JSON decoder or Ed25519 verifier allocates additional memory.
(define keyward-update-maximum-manifest-bytes (* 1024 1024))

(define (preview-keyward-update signed-manifest-bytes
                                #:user-initiated? user-initiated?
                                #:trusted-public-key trusted-public-key
                                #:expected-key-id expected-key-id
                                #:current-version current-version
                                #:install-kind install-kind
                                #:platform [platform (platform-symbol)]
                                #:architecture [architecture (architecture-symbol)])
  (unless user-initiated?
    (raise-arguments-error
     'preview-keyward-update
     "security vault update checks require explicit user action"))
  (unless (and (string? expected-key-id)
               (positive? (string-length expected-key-id)))
    (raise-arguments-error
     'preview-keyward-update
     "a pinned, non-empty update signing key ID is required"))
  (unless (bytes? signed-manifest-bytes)
    (raise-argument-error 'preview-keyward-update
                          "bytes?" signed-manifest-bytes))
  (when (> (bytes-length signed-manifest-bytes)
           keyward-update-maximum-manifest-bytes)
    (raise-arguments-error
     'preview-keyward-update
     "signed manifest exceeds the configured metadata size limit"
     "bytes" (bytes-length signed-manifest-bytes)
     "limit" keyward-update-maximum-manifest-bytes))
  (unless (memq install-kind '(portable msi appimage package-manager))
    (raise-arguments-error
     'preview-keyward-update
     "an explicit supported installation kind is required"
     "install kind" install-kind))
  (define verified
    (verify-signed-manifest (open-input-bytes signed-manifest-bytes)
                            trusted-public-key
                            #:key-id expected-key-id))
  (define config
    (updater-config keyward-update-application-id
                    current-version 'stable
                    platform architecture trusted-public-key
                    expected-key-id 0 keyward-update-maximum-bytes 'app))
  (define candidate (select-update config verified
                                   #:install-kind install-kind))
  (when candidate
    ;; The signer must bind downloads to this exact immutable release tag.
    ;; A signed moving latest URL could otherwise change between preview
    ;; and download, especially if the host later adds resume support.
    (define artifact-url
      (update-artifact-url (update-candidate-artifact candidate)))
    (define prefix
      (format "https://github.com/turlamai/keyward/releases/download/v~a/"
              (update-manifest-version verified)))
    (define name
      (and (string-prefix? artifact-url prefix)
           (substring artifact-url (string-length prefix))))
    (unless (and name
                 (regexp-match? #px"^[A-Za-z0-9][A-Za-z0-9._+-]*$" name)
                 (not (string-contains? name "..")))
      (raise-arguments-error
       'preview-keyward-update
       "signed asset is not pinned to the official immutable release tag"
       "url" artifact-url "expected prefix" prefix)))
  (when (and candidate
             (> (update-artifact-size (update-candidate-artifact candidate))
                keyward-update-maximum-bytes))
    (raise-arguments-error
     'preview-keyward-update
     "signed update exceeds maximum permitted download size"
     "bytes" (update-artifact-size (update-candidate-artifact candidate))
     "limit" keyward-update-maximum-bytes))
  ;; Returning a candidate does *not* authorize a network request, download,
  ;; installer launch, or key-vault file modification. That requires a later
  ;; explicit user confirmation and native-host handoff.
  candidate)
