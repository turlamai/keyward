#lang racket/base

;; Release identity: the single source the carrier, the update-check trust
;; root and scripts/check-release-version.sh read. Bump here, in VERSION and
;; in the CHANGELOG section together; the release gate cross-checks the three.
;; (racket/core/version.rkt replaced the rivet-staged app metadata when the UI
;; moved to glaze: no rivet build stages a metadata file any more.)

(define app-version "0.1.0")
;; Build number of this release line; the signed update feed carries it.
(define app-build 1)
(define app-identifier "site.jrtx.keyward")
(define app-release-channel "stable")

(provide app-version
         app-build
         app-identifier
         app-release-channel)
