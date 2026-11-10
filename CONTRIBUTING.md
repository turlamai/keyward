# Contributing to Keyward

Thank you for looking under the hood. Keyward is free software
(AGPL-3.0, see [LICENSE](LICENSE)): by submitting a pull request you
agree your contribution is licensed under AGPL-3.0.

Keyward follows the Rivet application architecture: Racket owns domain
logic, native hosts own UI, and the contract between them lives in
`app/backend.rkt` (RVT1) plus `rivet-schema.json`. Keep that split
intact.

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
   not contact a server or self-apply updates. `app/update-policy.rkt`
   is the pure offline trust boundary (user-initiated checks, pinned
   Ed25519 key, immutable tag URL, size caps); anything that downloads
   or installs without explicit user action is a critical regression.
4. **The wire contract is cross-platform.** Changing any RPC in
   `app/backend.rkt` is a three-platform release: regenerate the
   checked-in clients with `raco rivet build`
   (`macos-host/Sources/RivetHost/GeneratedBackend.swift`,
   `windows/GeneratedBackend.hpp`, `linux/GeneratedBackend.hpp`) in the
   same commit — they are build inputs, never hand-edit them.
5. **Fail honestly.** A locked or missing vault degrades to a clear
   message, never a silent fallback or a wrong default; deep check
   reports per-entry findings instead of a single green dot.
6. **Tests pin contracts.** If you change behavior a test covers,
   change the test in the same commit and say why.

## Before you push

```bash
raco test tests/                       # engine tests (store + key metadata)
raco make app/backend.rkt              # backend compiles against the RVT1 contract
bash scripts/check-release-version.sh  # VERSION == rivet.rktd == CHANGELOG
raco rivet build                       # backend + current platform native host
```

These mirror the CI `engine` job; the platform hosts compile in their
own CI jobs. If you touch `macos-host/`, `windows/` or `linux/`, say
whether you were able to build locally.

## Releasing

Releases are tag-driven (`v*`); the workflow gates on
`scripts/check-release-version.sh`, clean rebuilds and a release
acceptance smoke against a synthetic vault. A release bump moves
`VERSION`, `rivet.rktd` and the dated `## [X.Y.Z] - YYYY-MM-DD`
CHANGELOG entry in the same commit. The release ships installers only —
no update feed (`raco rivet release --without-updates`), per rule 3.

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
