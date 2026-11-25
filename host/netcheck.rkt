#lang racket/base

;; Listening-socket evidence for the zero-network claim (#34 S0).
;;
;; The vault engine performs no network I/O. The carrier's transport is
;; glaze's native GLZ1 channel, which opens no listener either, so a running
;; Keyward must own no listening TCP socket. Racket 9.3 exposes no listener
;; table of its own, so this asks the operating system about THIS process:
;; lsof on macOS/Linux, Get-NetTCPConnection on Windows.
;;
;;   (listening-tcp-ports) -> (listof string?)   ports this process listens on
;;                        -> 'unknown             the OS query itself failed
;;
;; 'unknown is never treated as "none" by the self-check.

(require ffi/unsafe
         ffi/unsafe/define
         racket/format
         racket/list
         racket/port
         racket/file
         racket/string
         racket/system)

(define libc
  (case (system-type)
    [(windows) (ffi-lib "msvcrt.dll")]
    [else (ffi-lib #f)]))

(define-ffi-definer define-c libc)

(define-c getpid (_fun -> _int) #:c-id _getpid)

(define (process-id) (getpid))

;; Runs the query; -> (cons status text). stderr is discarded.
(define (run cmd args)
  (define out-path (make-temporary-file "keyward-netcheck-~a.out"))
  (define err-path (make-temporary-file "keyward-netcheck-~a.err"))
  (define out-file (open-output-file out-path #:exists 'truncate))
  (define err-file (open-output-file err-path #:exists 'truncate))
  (define-values (p _stdout _stdin _stderr)
    (apply subprocess out-file #f err-file cmd args))
  (close-output-port out-file)
  (close-output-port err-file)
  (subprocess-wait p)
  (define status (subprocess-status p))
  (define text (with-handlers ([exn:fail? (lambda (_) "")]) (file->string out-path)))
  (delete-file out-path)
  (delete-file err-path)
  (cons status text))
;; lsof -Fn prints one name per line: "n127.0.0.1:41234" or "n*:8080".
(define (lsof-ports text)
  (for/list ([line (in-list (string-split text "\n"))]
                #:when (string-prefix? line "n")
                #:when (regexp-match? #rx":" line))
    (car (reverse (string-split (string-trim line) ":")))))

(define (windows-ports text)
  (filter (lambda (s) (positive? (string-length s)))
          (string-split (string-trim text) #px"\\s+")))

(define (listening-tcp-ports)
  (define pid (process-id))
  (if (eq? (system-type 'os) 'windows)
      (match-run (run (find-executable-path "powershell")
                      (list "-NoProfile" "-NonInteractive" "-Command"
                            (format "if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) { exit 2 }; $c = Get-NetTCPConnection -State Listen -OwningProcess ~a -ErrorAction SilentlyContinue; if ($c) { $c | ForEach-Object { $_.LocalPort } }; exit 0" pid)))
                 windows-ports)
      (let ([result (run "lsof" (list "-a" "-Pan" "-p" (~a pid) "-iTCP" "-sTCP:LISTEN" "-Fn"))])
        (cond
          ;; lsof exits 1 when nothing matched: no listening socket.
          [(= (car result) 1) '()]
          [else (match-run result lsof-ports)]))))
;; -> parsed ports on exit 0; 'unknown on any other status.
(define (match-run result parse)
  (if (= (car result) 0) (parse (cdr result)) 'unknown))

(provide process-id
         listening-tcp-ports)
