#lang racket/base

;; Source-run verifier: the same real-window journey as the packaged
;; self-check (host/main.rkt), without a build. Writes the verdict and the
;; step report to .glaze/verify/selftest.json and a screenshot on platforms
;; where a capture is safe.
;;
;;   racket host/verify.rkt            exit 0 = every step passed

(require racket/file
         racket/runtime-path
         racket/system)

(define-runtime-path here ".")
(define root (simplify-path (build-path here 'up)))
(define evidence (build-path root ".glaze" "verify"))
(make-directory* evidence)

(putenv "KEYWARD_SELFTEST" "1")
(putenv "KEYWARD_SELFTEST_OUT" (path->string (build-path evidence "selftest.json")))
(unless (eq? (system-type 'os) 'linux)
  (putenv "KEYWARD_SHOT" (path->string (build-path evidence "keyward-e2e.png"))))

(void (dynamic-require `(submod ,(build-path root "host" "main.rkt") main) #f))
