#lang racket/base

;; Harness isolation, and it must run BEFORE the backend module initializes.
;;
;; host/main.rkt requires this module first: Racket instantiates a module's
;; dependencies in order, and racket/backend.rkt selects the startup vault in
;; a top-level expression. With KEYWARD_E2E=1 or KEYWARD_SELFTEST=1 the
;; process must never see the user's vault, so the config directory and the
;; KEYWARD_STORE override are pointed aside before that selection happens.
(require racket/file)

(define (flag->string name)
  (getenv name))

(define harness?
  (or (equal? (flag->string "KEYWARD_E2E") "1")
      (equal? (flag->string "KEYWARD_SELFTEST") "1")))

(when harness?
  (putenv "KEYWARD_E2E" "1")
  ;; A scratch config dir: store-open persists the chosen vault path there.
  (unless (let ([v (flag->string "KEYWARD_CONFIG_DIR")])
            (and v (positive? (string-length v))))
    (putenv "KEYWARD_CONFIG_DIR"
            (path->string (make-temporary-file "keyward-e2e-config-~a" 'directory))))
  ;; The env override would select a vault at startup; drop it so only the
  ;; fixture vault is ever opened.
  (putenv "KEYWARD_STORE" ""))

(provide harness?)
