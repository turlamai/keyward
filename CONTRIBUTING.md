# Contributing to Keyward

Thank you for looking under the hood. Keyward is free software
(AGPL-3.0, see [LICENSE](LICENSE)): by submitting a pull request you
agree your contribution is licensed under AGPL-3.0.

Keyward follows the Rivet application architecture with a glaze carrier:
Racket owns domain logic (`racket/backend.rkt`, RVT1, `rivet-schema.json`),
and one carrier (`host/`) owns the UI on the system WebView. Keep that split
intact: the page renders and relays; the engine decides.

## Ground rules

1. **Key values never display.** Raw key material leaves the process
   only through the explicit copy-to-clipboard RPC, with the exposure
   disclosure and the 30 s auto-clear. Listings, deep-check and scan
   results carry names, counts and fingerprints only. This is the
   product's first invariant — a new surface that renders a value is a
   bug, not a feature.
2. **Plaintext custody stays disclosed, never silently "upgraded".**
   The vault file and its snapshots are plain INI by design, and every
   surface says so. Do not add encryption, obfuscation or network calls
   without changing the product contract first
   ([docs/UPDATE-SECURITY.md](docs/UPDATE-SECURITY.md), `AGENTS.md`).
3. **Manual-update-only is an intentional exemption.** A key vault does
   not contact a server or self-apply updates. `racket/update-policy.rkt`
   is the pure offline trust boundary (user-initiated checks, pinned
   Ed25519 key, immutable tag URL, size caps); anything that downloads
   or installs without explicit user action is a critical regression.
4. **The wire contract is cross-platform.** Changing any RPC in
   `racket/backend.rkt` changes every platform at once: regenerate
   `glaze-schema.json` (`raco glaze schema write`) in the same commit and
   keep `scripts/check-rpc-surface.py` green. `entry-get` and
   `keypair-export` are carrier-only — never route them to the page.
5. **Fail honestly.** A locked or missing vault degrades to a clear
   message, never a silent fallback or a wrong default; deep check
   reports per-entry findings instead of a single green dot.
6. **Tests pin contracts.** If you change behavior a test covers,
   change the test in the same commit and say why.

## Before you push

```bash
raco test tests/                       # engine tests (store + key metadata)
raco make racket/backend.rkt           # backend compiles against the RVT1 contract
bash scripts/check-release-version.sh  # VERSION == version.rkt == CHANGELOG
racket host/verify.rkt                 # real-window carrier: 19-step journey
```

These mirror the CI `engine` job and the `host-ci` carrier job. The carrier
is exercised on Windows, macOS and Linux in CI; say whether you were able to
run `host/verify.rkt` locally.

## Releasing

Releases are tag-driven (`v*`); the workflow gates on
`scripts/check-release-version.sh`, a packaged product journey on Linux, and
the macOS signing secrets. A release bump moves `VERSION`,
`racket/core/version.rkt` and the dated `## [X.Y.Z] - YYYY-MM-DD` CHANGELOG
entry in the same commit. macOS is Developer ID-signed and notarized;
Windows and Linux installers are unsigned for now and the notes say so. The
release publishes a signed update feed (`update-manifest.json`) but Keyward
still has no in-app updater, per rule 3.

## Areas that especially want help

- The future user-initiated "Check for Updates" flow per the
  [docs/UPDATE-SECURITY.md](docs/UPDATE-SECURITY.md) contract (issue
  #15) — UI, native install handoffs and CI acceptance gates.
- Keeping the Chinese user path in lockstep with the English one
  (`README.zh-CN.md`, `docs/USER-GUIDE.zh-CN.md`) — the language policy
  in [AGENTS.md](AGENTS.md) requires reciprocal updates.

## Reporting issues

Include: OS + version, Keyward version (Help ▸ About), install shape
(DMG / MSI / portable zip / AppImage / deb / rpm / tarball), steps to
reproduce, and what Deep Check reported. **Never paste key values or
vault section bodies into an issue** — fingerprints are the shareable
identifier. Security issues go through [SECURITY.md](SECURITY.md), not
public issues.
