#lang racket/base

;; Keyward glaze carrier (#34): the single web UI's host adapter.
;;
;; S0 (carrier skeleton): the glaze app shell on the NATIVE GLZ1 transport
;; (no listening socket: a product that promises "the engine has no network
;; operations" must not open a loopback port either), the runtime public dir
;; (token sheet served single-source from design/prototype/shared.css) and
;; the real-window verifier / packaged self-check.
;;
;; S1 (RPC bridge): racket/backend.rkt is unchanged; this module drives the
;; production backend over real in-process RVT1 frames through rivet/backend's
;; serve loop and rivet/bridge. rivet-schema.json remains the single source of
;; the RPC contract: the bridge codec converts camelCase JSON DTOs to
;; field-ordered wire values and back; scripts/check-rpc-surface.py gates the
;; route surface against the schema.
;;
;; Two RPCs are deliberately NOT routed to the page: entry-get and
;; keypair-export return secret values. Values travel backend -> clipboard
;; inside the carrier only (api/host/copy); the page never receives one.
;;
;; Run:        racket host/main.rkt
;; Self-check: KEYWARD_SELFTEST=1 racket host/main.rkt   (or host/verify.rkt)

(require "e2e-config.rkt" ; must stay first: isolation before the backend initializes
         "netcheck.rkt"
         glaze/app        ; run-app
         glaze/api        ; GET, POST, exn:fail:glaze:bad-param
         glaze/api-macros ; define-api-routes
         glaze/capability ; make-capability
         glaze/dialogs    ; make-dialog-routes (native open panel)
         glaze/sys/main   ; clipboard-set!, clipboard-get
         glaze/window     ; webview-title, webview-navigate, webview-capture!, webview-close
         glaze/types      ; GString, GBool, GValue
         (prefix-in core: "../racket/core/version.rkt")
         (prefix-in engine: "../racket/backend.rkt")
         racket/file
         racket/format
         racket/list
         racket/math
         racket/path
         racket/runtime-path
         racket/string
         ffi/unsafe/atomic
         json
         net/base64
         rivet/backend    ; serve (the RVT1 serve loop over a pipe pair)
         rivet/bridge)

;; The route list schema tooling reads (glaze.rktd points here). start-engine!
;; wires the codec to the in-process RVT1 transport; schema checks load this
;; module without starting anything.
(provide api start-engine! stop-engine! assemble-public-dir app-version host-capability
         journey-step-count)

(define-runtime-path schema-path "../rivet-schema.json")
(define schema (call-with-input-file schema-path read-json))
(define codec (make-bridge-codec schema))

(define app-version core:app-version)

;; ---- one RPC call, JSON in / JSON out ------------------------------------

(define (bad-param message)
  (raise (exn:fail:glaze:bad-param message (current-continuation-marks))))

(define (rpc/json name args)
  (define sym (string->symbol name))
  (when (getenv "KEYWARD_TRACE") (eprintf "[trace] rpc ~a\n" name))
  (define wire-args (bridge-codec-encode codec sym args))
  (define-values (result err) (apply bridge-call name wire-args))
  ;; The backend's message is the user-facing message. bad-param is the
  ;; framework's typed channel whose message reaches the page.
  (when err (bad-param (format "~a" err)))
  (bridge-codec-decode codec sym result))

;; Secret-bearing RPCs: carrier-internal only, never in `api`.
(define (rpc/secret name args)
  (define value (rpc/json name args))
  (unless (string? value) (bad-param (format "~a: no value" name)))
  value)

;; ---- typed RPC surface (rivet-schema.json minus the two secret RPCs) ----

(define-api-routes api-rpc
  [(POST "api/rpc/store-path" #:returns GString #:permission 'rpc)
   (rpcStorePath)
   (rpc/json "store-path" (hasheq))]
  [(POST "api/rpc/store-open" #:returns GString #:permission 'rpc)
   (rpcStoreOpen [path GString])
   (rpc/json "store-open" (hasheq 'path path))]
  [(POST "api/rpc/store-info" #:returns GValue #:permission 'rpc)
   (rpcStoreInfo)
   (rpc/json "store-info" (hasheq))]
  [(POST "api/rpc/check-store" #:returns GValue #:permission 'rpc)
   (rpcCheckStore)
   (rpc/json "check-store" (hasheq))]
  [(POST "api/rpc/entry-list" #:returns GValue #:permission 'rpc)
   (rpcEntryList [product GString])
   (rpc/json "entry-list" (hasheq 'product product))]
  [(POST "api/rpc/entry-set" #:returns GString #:permission 'rpc)
   (rpcEntrySet [product GString] [name GString] [value GString])
   (rpc/json "entry-set" (hasheq 'product product 'name name 'value value))]
  [(POST "api/rpc/entry-delete" #:returns GBool #:permission 'rpc)
   (rpcEntryDelete [product GString] [name GString])
   (rpc/json "entry-delete" (hasheq 'product product 'name name))]
  [(POST "api/rpc/entry-import-file" #:returns GString #:permission 'rpc)
   (rpcEntryImportFile [product GString] [name GString] [filePath GString])
   (rpc/json "entry-import-file"
             (hasheq 'product product 'name name 'filePath filePath))]
  [(POST "api/rpc/keypair-generate" #:returns GValue #:permission 'rpc)
   (rpcKeypairGenerate [product GString])
   (rpc/json "keypair-generate" (hasheq 'product product))]
  [(POST "api/rpc/rotation-start" #:returns GValue #:permission 'rpc)
   (rpcRotationStart [product GString])
   (rpc/json "rotation-start" (hasheq 'product product))]
  [(POST "api/rpc/rotation-promote" #:returns GValue #:permission 'rpc)
   (rpcRotationPromote [product GString])
   (rpc/json "rotation-promote" (hasheq 'product product))]
  [(POST "api/rpc/rotation-cancel" #:returns GBool #:permission 'rpc)
   (rpcRotationCancel [product GString])
   (rpc/json "rotation-cancel" (hasheq 'product product))]
  [(POST "api/rpc/rotation-status" #:returns GValue #:permission 'rpc)
   (rpcRotationStatus [product GString])
   (rpc/json "rotation-status" (hasheq 'product product))]
  [(POST "api/rpc/snapshot-list" #:returns GValue #:permission 'rpc)
   (rpcSnapshotList)
   (rpc/json "snapshot-list" (hasheq))]
  [(POST "api/rpc/snapshot-restore" #:returns GBool #:permission 'rpc)
   (rpcSnapshotRestore [stamp GString])
   (rpc/json "snapshot-restore" (hasheq 'stamp stamp))]
  [(POST "api/rpc/stray-scan-tree" #:returns GValue #:permission 'rpc)
   (rpcStrayScanTree [dir GString])
   (rpc/json "stray-scan-tree" (hasheq 'dir dir))]
  [(POST "api/rpc/update-check" #:returns GValue #:permission 'rpc)
   (rpcUpdateCheck [manifest GString] [installKind GString] [linuxPackageFormat GString])
   (rpc/json "update-check"
             (hasheq 'manifest manifest 'installKind installKind
                     'linuxPackageFormat linuxPackageFormat))])

;; ---- host capabilities (outside any RPC surface gate) ------------------

;; The clipboard lifetime in seconds; the page shows the countdown, the
;; carrier owns the clock.
(define copy-lifetime-seconds 30)

(define clip-lock (make-semaphore 1))
;; The copied text stays in carrier memory only: never logged, never answered
;; to the page. Cleared as soon as the expiry ran.
(define clip-value (box #f))
(define clip-state (box (hasheq 'state "idle" 'name "" 'deadline 0)))

(define (clip-now) (current-inexact-milliseconds))

;; Host-enforced auto-clear (#34 S0): the timer lives in the carrier, so it
;; survives a page reload and cannot be skipped by page code. The clipboard is
;; erased only while it still holds exactly what this action put there; a
;; later copy by the user is never touched.
(define (clip-expire! expected-value deadline)
  (define wait (/ (- deadline (clip-now)) 1000.0))
  (when (positive? wait) (sleep wait))
  (call-with-semaphore
   clip-lock
   (lambda ()
     (when (eq? (unbox clip-value) expected-value)
       (cond
         [(not (string=? (clipboard-get) expected-value))
          (set-box! clip-value #f)
          (set-box! clip-state (hash-set (unbox clip-state) 'state "kept"))]
         [(clipboard-set! "")
          (set-box! clip-value #f)
          (set-box! clip-state (hash-set (unbox clip-state) 'state "cleared"))]
         [else
          ;; The OS refused the clear: say so instead of claiming success.
          (set-box! clip-value #f)
          (set-box! clip-state (hash-set (unbox clip-state) 'state "kept"))])))))

(define (host-copy! product name format)
  (define value
    (if (string=? format "")
        (rpc/secret "entry-get" (hasheq 'product product 'name name))
        (rpc/secret "keypair-export"
                    (hasheq 'product product 'name name 'format format))))
  (unless (clipboard-set! value) (bad-param "the system clipboard refused the copy"))
  (define deadline (+ (clip-now) (* copy-lifetime-seconds 1000)))
  (call-with-semaphore
   clip-lock
   (lambda ()
     (set-box! clip-value value)
     (set-box! clip-state (hasheq 'state "copied" 'name name 'deadline deadline))))
  (thread (lambda () (clip-expire! value deadline)))
  (hasheq 'ok #t 'seconds copy-lifetime-seconds))

(define (clip-json)
  (define s (unbox clip-state))
  (hasheq 'state (hash-ref s 'state "idle")
          'name (hash-ref s 'name "")
          'secondsLeft
          (max 0 (exact-floor (/ (- (hash-ref s 'deadline 0) (clip-now)) 1000.0)))))

;; ---- acceptance harness gate --------------------------------------------
;; Inert unless KEYWARD_E2E=1 (verify.rkt / CI / the packaged self-check).

(define (e2e-enabled?) (equal? (getenv "KEYWARD_E2E") "1"))
(define e2e-report-box (box #f))

;; A disposable vault with two products that need attention and one without
;; entries; the journey generates real keys through the product.
(define fixture-vault
  (string-append
   ;; alpha: two empty non-key entries and no signing key yet (the journey
   ;; generates one); beta: a private key with an empty value (unreadable);
   ;; gamma: no entries.
   "[alpha]\nLICENSE_OWNER =\nKEY_CREATED_AT =\n"
   "[beta]\nLICENSE_ED25519_PRIVATE_KEY_B64 =\nLICENSE_PUBLIC_KEY_B64 =\n"
   "[gamma]\n"))

(define (e2e-fixtures)
  (unless (e2e-enabled?) (bad-param "journey fixtures: harness not enabled"))
  (define root (make-temporary-file "keyward-e2e-~a" 'directory))
  (define vault (build-path root "vault.ini"))
  (display-to-file fixture-vault vault #:exists 'truncate/replace)
  (hasheq 'vaultPath (path->string vault)
          'strayPath (path->string (build-path root "release-workspace"))))

;; Plant a PEM private key block outside the vault for the stray-key scan.
(define (e2e-stray-seed!)
  (unless (e2e-enabled?) (bad-param "stray fixture: harness not enabled"))
  (define root (make-temporary-file "keyward-e2e-stray-~a" 'directory))
  (define dir (build-path root "release-workspace"))
  (make-directory* dir)
  (display-to-file
   (string-append "# rotation checklist\n"
                   "-----BEGIN PRIVATE KEY-----\n"
                   "MC4CAQAwBQYDK2VwBCIEIHkQ+qZqSXMVXAyDmyWgquFn0WqLUoGh\n"
                   "-----END PRIVATE KEY-----\n")
   (build-path dir "signing-notes.md")
   #:exists 'truncate/replace)
  (path->string root))

;; Journey fixture: is the clipboard holding this entry's value right now?
;; Answers a boolean only; the value never leaves the carrier.
(define (e2e-clipboard-matches? product name)
  (unless (e2e-enabled?) (bad-param "clipboard fixture: harness not enabled"))
  (define value (rpc/secret "entry-get" (hasheq 'product product 'name name)))
  (string=? (clipboard-get) value))

;; A public-key PEM outside the vault for the import journey step.
(define (e2e-import-seed!)
  (unless (e2e-enabled?) (bad-param "import fixture: harness not enabled"))
  (define root (make-temporary-file "keyward-e2e-import-~a" 'directory))
  (define file (build-path root "license-pub.pem"))
  ;; SPKI of an ed25519 public key (prefix + 32 bytes): a well-formed anchor.
  (define spki
    (list->bytes
     (append (bytes->list (bytes #x30 #x2a #x30 #x05 #x06 #x03 #x2b #x65 #x70 #x03 #x21 #x00))
             (build-list 32 add1))))
  (define b64 (bytes->string/utf-8 (base64-encode spki "\n")))
  (display-to-file
   (string-append "-----BEGIN PUBLIC KEY-----\n" b64 "\n-----END PUBLIC KEY-----\n")
   file #:exists 'truncate/replace)
  (path->string file))

(define (e2e-report! payload)
  (when (getenv "KEYWARD_TRACE") (eprintf "[trace] report ~a\n" (jsexpr->string payload)))
  (when (e2e-enabled?) (set-box! e2e-report-box payload))
  #t)

(define-api-routes api-host
  [(GET "api/health" #:permission 'host #:returns GValue)
   (healthHost)
   (hasheq 'ok #t 'version app-version 'carrier "glaze")]

  [(GET "api/host/context" #:permission 'host #:returns GValue)
   (hostContext)
   (when (getenv "KEYWARD_TRACE") (eprintf "[trace] context\n"))
   (hasheq 'version app-version
           'transport "native"
           'copySeconds copy-lifetime-seconds
           'e2e (e2e-enabled?))]

  ;; Copy is the value's only exit: the value goes backend -> clipboard inside
  ;; the carrier and is never answered to the page.
  [(POST "api/host/copy" #:permission 'clipboard #:returns GValue)
   (hostCopy [product GString] [name GString] [format GString ""])
   (host-copy! product name format)]

  [(GET "api/host/clipboard" #:permission 'clipboard #:returns GValue)
   (hostClipboard)
   (clip-json)]

  [(POST "api/host/e2e-fixtures" #:permission 'e2e #:returns GValue)
   (e2eFixtures)
   (e2e-fixtures)]

  [(POST "api/host/e2e-stray-seed" #:permission 'e2e #:returns GString)
   (e2eStraySeed)
   (e2e-stray-seed!)]

  [(POST "api/host/e2e-clipboard" #:permission 'e2e #:returns GBool)
   (e2eClipboard [product GString] [name GString])
   (e2e-clipboard-matches? product name)]

  [(POST "api/host/e2e-import-seed" #:permission 'e2e #:returns GString)
   (e2eImportSeed)
   (e2e-import-seed!)]

  [(POST "api/host/e2e-report" #:permission 'e2e #:returns GBool)
   (e2eReport [payload GValue])
   (e2e-report! payload)]

  [(POST "api/host/e2e-reset" #:permission 'e2e #:returns GBool)
   (e2eReset)
   (when (e2e-enabled?) (set-box! e2e-report-box #f))
   #t])

(define api (append api-rpc api-host (make-dialog-routes)))

;; Runtime authority for the production window. Under a capability the
;; carrier is default-deny: only granted classes answer. `rpc` is the RPC
;; bridge (entry-get / keypair-export are not in it), `host` is context,
;; `clipboard` is the copy path and its state, `dialog:open` is the native
;; open panel (vault file, PEM file, scan folder), `e2e` is the harness (inert
;; unless the gate is on). A route without a permission is refused in
;; production; scripts/check-route-permissions.py makes that a static failure.
(define host-capability
  (make-capability "keyward" '(rpc host clipboard dialog:open e2e)))

;; ---- runtime public dir ---------------------------------------------------
;; The token sheet (design/prototype/shared.css) stays single-source in the
;; repo; the carrier assembles a runtime public dir at startup.
(define-runtime-path web-dir "web")
(define-runtime-path shared-css-path "../design/prototype/shared.css")

(define (assemble-public-dir)
  (define dir (build-path (find-system-path 'temp-dir)
                          (format "keyward-public-~a-~a"
                                  (current-seconds) (current-inexact-milliseconds))))
  (copy-directory/files web-dir dir)
  (copy-file shared-css-path (build-path dir "shared.css"))
  dir)

;; ---- in-process engine transport -----------------------------------------
;; The backend serves RVT1 over a pipe pair inside this process (static
;; require above keeps raco exe embedding working).
(define engine-started? #f)

(define (serve/ports)
  (define-values (c2s-in c2s-out) (make-pipe))
  (define-values (s2c-in s2c-out) (make-pipe))
  (define srv (thread (lambda () (serve c2s-in s2c-out))))
  (values srv s2c-in c2s-out))

(define (start-engine!)
  (unless engine-started?
    (start-bridge! serve/ports)
    (when (e2e-enabled?) (engine:select-store! #f))
    (set! engine-started? #t)))

;; Idempotent shutdown for the app entry and the verifier.
(define (stop-engine!)
  (when engine-started?
    (stop-bridge!)
    (set! engine-started? #f)))

;; ---- journey (real window, production path) ------------------------------
;; glaze exposes no JS injection into the webview, so the page carries an
;; in-page journey harness (?e2e=1) that reports after every step.
(define journey-step-count 19)

(define (wait-title! wv)
  (define deadline (+ (current-inexact-milliseconds) 45000))
  (let loop ()
    (cond
      [(and (string? (webview-title wv)) (string-prefix? (webview-title wv) "Keyward")) #t]
      [(>= (current-inexact-milliseconds) deadline) #f]
      [else (sleep 0.1) (loop)])))

(define (await-report!)
  (define budget
    (or (let ([v (getenv "KEYWARD_SELFTEST_TIMEOUT_MS")])
          (and v (string->number v)))
        300000))
  (define deadline (+ (current-inexact-milliseconds) budget))
  (let loop ()
    (define r (unbox e2e-report-box))
    (cond
      [(and (hash? r) (member (hash-ref r 'phase #f) '("done" "timeout"))) r]
      [(>= (current-inexact-milliseconds) deadline)
       ;; A hung step must still leave its trace: report the last progress.
       (define last (unbox e2e-report-box))
       (if (hash? last) last (hasheq 'phase "timeout" 'ok #f 'stepCount 0 'steps (hasheq)))]
      [else (sleep 0.25) (loop)])))

(define note-box (box '()))
(define (note! . args)
  (set-box! note-box (append (unbox note-box) (list (apply format args)))))

;; Runs inside #:on-ready. A failure anywhere is a failed verdict, never an
;; exception: the report must reach CI.
(define (journey-run! wv url)
  (with-handlers ([exn:fail? (lambda (e)
                               (note! "error: ~a" (exn-message e))
                               (list (cons 'window-booted #f)))])
    (define booted? (wait-title! wv))
    (note! "first load: title ~s url ~s" (webview-title wv) (webview-url wv))
    ;; The page asks the carrier whether the harness is on (host/web/e2e.js),
    ;; so the first load already runs the journey; no re-navigation is needed.
    (define report (await-report!))
    ;; Optional evidence (KEYWARD_SHOT=<png>): never on Linux, where a
    ;; capture taken while the native channel is open kills the carrier.
    (define shot (getenv "KEYWARD_SHOT"))
    (when (and shot (positive? (string-length shot)) (not (eq? (system-type 'os) 'linux)))
      (with-handlers ([exn:fail? (lambda (e) (note! "capture: ~a" (exn-message e)))])
        (define png (webview-capture! wv))
        (when (in-atomic-mode?) (end-atomic))
        (when (and (string? png) (file-exists? png)) (copy-file png shot #:exists? 'replace))))
    (define steps (hash-ref report 'steps (hasheq)))
    (define step-count (hash-count steps))
    (note! "report: ~a" (jsexpr->string report))
    (define listeners (listening-tcp-ports))
    (note! "listening tcp sockets of this process: ~a" listeners)
    (list (cons 'window-booted booted?)
          (cons 'report-done (equal? (hash-ref report 'phase #f) "done"))
          (cons 'journey-ok (eq? #t (hash-ref report 'ok #f)))
          (cons 'step-count (and (= journey-step-count (hash-ref report 'stepCount 0))
                                 (= journey-step-count step-count)))
          (cons 'steps-ok (and (positive? step-count)
                               (for/and ([s (in-hash-values steps)])
                                 (and (hash? s) (eq? #t (hash-ref s 'ok #f))))))
          ;; Zero-network evidence: the native transport opens no listener.
          (cons 'no-listener (null? listeners)))))

(define (journey-finish! verdict)
  (define ok? (and (pair? verdict) (andmap cdr verdict)))
  (define out (getenv "KEYWARD_SELFTEST_OUT"))
  (when (and out (positive? (string-length out)))
    (define dir (path-only out))
    (when dir (make-directory* dir))
    (call-with-output-file out
      (lambda (p)
        (write-json (hasheq 'ok ok?
                            'verdict (for/hasheq ([v (in-list verdict)]) (values (car v) (cdr v)))
                            'report (or (unbox e2e-report-box) (hasheq))
                            'notes (unbox note-box))
                    p)
        (newline p))
      #:exists 'truncate/replace))
  (for ([v (in-list verdict)])
    (printf "[selftest] ~a = ~a\n" (car v) (if (cdr v) "#t" "#f")))
  (for ([note (in-list (unbox note-box))])
    (printf "[selftest] ~a\n" note))
  (cond
    [ok? (displayln "[selftest] ALL PASS")]
    [else (eprintf "[selftest] self-check failed\n")])
  (flush-output)
  (exit (if ok? 0 1)))

(module+ main
  (define selftest? (equal? (getenv "KEYWARD_SELFTEST") "1"))
  (define verdict-box (box #f))
  (start-engine!)
  (define-values (_kind stop)
    (run-app
     #:public-dir (assemble-public-dir)
     #:api api
     ;; on-ready must return at once: the WebView message loop (which carries
     ;; GLZ1 requests and responses on the native channel) only runs once the
     ;; event loop owns the window, so the journey waits in its own thread and
     ;; closes the window when it is done.
     #:on-ready (lambda (wv url)
                  (when selftest?
                    (thread (lambda ()
                              (set-box! verdict-box (journey-run! wv url))
                              (webview-close wv)))))
     ;; The native GLZ1 channel: no loopback listener. KEYWARD_TRANSPORT=http
     ;; is a development fallback only.
     #:transport (if (equal? (getenv "KEYWARD_TRANSPORT") "http") 'http 'native)
     #:title "Keyward"
     #:width 1180
     #:height 740
     #:current-version app-version
     #:capability host-capability
     #:app-id "keyward"))
  (stop-engine!)
  (stop)
  (when selftest?
    (journey-finish! (or (unbox verdict-box) (list (cons 'window-opened #f))))))
