# Keyward

**English** · [中文](README.zh-CN.md)

A local vault for the release-signing keys of self-updating desktop apps.

[![CI](https://github.com/turlamai/keyward/actions/workflows/ci.yml/badge.svg)](https://github.com/turlamai/keyward/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/turlamai/keyward)](https://github.com/turlamai/keyward/releases)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

Every app that updates itself over the network eventually relies on the same
trust model: a **private key signs the update manifest**, and a **public key
embedded in the installed app** verifies it. Sparkle, Tauri's updater,
electron-updater, WinSparkle, Google Omaha — the scheme is universal. What
nobody hands you is custody for the private half: where it lives, how it
reaches CI, when it rotates, and how you notice a stray copy before it
rotates *you*.

> 📖 **New to update signing?** Read the bilingual handbook —
> **[使用手册 / Handbook](https://keyward.jrtx.site/guide.html)** (中文原文，
> with an idiomatic English translation; switchable per language) —
> or the [source markdown](docs/manual.zh-CN.md): install, connect a vault,
> every daily operation, wiring CI, shipping updates, and key rotation,
> written for complete beginners.

Keyward is a small desktop app that guards those keys. A Racket engine behind one
Glaze carrier (the system WebView, one UI for macOS, Windows and Linux), it keeps
the vault file in your own synced folder and adds the discipline a plaintext store lacks:

- **Never displayed, copy-only.** Key values never reach the UI: a copy goes
  through the carrier straight to the clipboard, which announces its own exposure
  (any app can read the clipboard) and auto-clears after 30 s — unless you have
  copied something else in between, which is never erased.
- **Loss protection.** Every mutation snapshots the store first (append-only,
  inside the synced folder); writes are atomic and permissions are tightened.
- **Deep check.** Parses each key (Ed25519 / RSA PKCS#8, base64-DER,
  base64-PEM or bare PEM), derives the public half, computes the fingerprint,
  and pairs it against the stored public material — the audit that used to be
  a pile of hand-run openssl commands. Every private entry is checked against
  all public anchors of the same purpose; a section passes only when every
  private key passes, with each fingerprint labelled in multi-key sections.
- **Collect, don't scatter.** In-app keypair generation writes straight into
  the vault; PEM imports land as single-line base64 values. No stray key
  files, even momentarily.
- **Orphan detection.** Multi-line residue from a bad paste shows up as line
  numbers the moment the vault is opened.
- **Rotation as a workflow.** Stage a next key under `UPDATE_ED25519_NEXT_*`
  without touching the active signing key, ship a release that trusts it,
  then Promote — the two-phase runbook, mechanized.
- **Stray sweep.** Scan a working tree for private-key material that never
  made it into the vault; hits report path, line and fingerprint, never values.
- **Speaks your updater's dialect.** Import Sparkle/minisign key files as-is
  and copy vault entries back out as Sparkle, Tauri/minisign or PEM —
  clipboard-only.

The vault format is plain INI (`[product]` sections, `NAME = value`,
comments preserved) and stays the single source of truth — Keyward is a
discipline layer over it, not a lock-in.

## Start here

Free release-infrastructure tool under AGPL-3.0; no commercial activation. Desktop previews for macOS, Windows and Linux. Use a synthetic disposable vault before connecting real release credentials.

[Installation, first use, privacy, backup and recovery](docs/USER-GUIDE.md) · [简体中文](docs/USER-GUIDE.zh-CN.md)

## Install

Download from [Releases](https://github.com/turlamai/keyward/releases/latest):

| Platform | Download | Updates |
|---|---|---|
| macOS 14+ (Apple Silicon & Intel) | `keyward-<version>-macos-<arch>.dmg` — `arm64` / `x64` — plus a portable `.zip` per arch | manual download only — a key vault does not update itself ([docs/UPDATE-SECURITY.md](docs/UPDATE-SECURITY.md)) |
| Windows 10+ x64 | `keyward-<version>-windows-x64.msi` installer, or `keyward-<version>-windows-x64.zip` portable | manual download only |
| Linux x64 / arm64 | `keyward-<version>-linux-x86_64.AppImage` / `keyward-<version>-linux-aarch64.AppImage`, `keyward-<version>-linux-<distro-arch>.deb`, `.rpm`, the Flatpak bundle `keyward-<version>-linux-<arch>.flatpak` (app id `site.jrtx.keyward`; `flatpak --user install ./keyward-<version>-linux-<arch>.flatpak`), the portable `tar.gz` | manual download only |

Every release carries a `SHA256SUMS` manifest, CycloneDX SBOMs and Sigstore
build provenance (`gh attestation verify <file> -R turlamai/keyward`).

macOS builds are Developer ID-signed and notarized. **The Windows installer is
not Authenticode-signed** (SmartScreen warns on first run) **and the Linux
packages are not vendor-signed** for now: verify Windows and Linux downloads
against `SHA256SUMS` or the attestations, not the installer signature.

## Status

**v0.1.0 of the Glaze line is out** — the release line started over when the
three native hosts (SwiftUI / WinUI 3 / GTK 4) were replaced by one carrier
and one UI; the earlier 0.1.0 – 0.3.0 releases were withdrawn. Installers for
all three desktops are on the
[Releases page](https://github.com/turlamai/keyward/releases/latest):
macOS (arm64 / x64, DMG + zip), Windows (x64, MSI + zip) and Linux (x64 /
arm64, deb + rpm + AppImage + Flatpak + tar.gz). The two-phase rotation
workflow, the stray-key scanner and Sparkle/Tauri key format import and
export carry over unchanged. The carrier opens no network socket: the page
talks to the engine over an in-process channel.

## Security model

The vault is plaintext **by design** — it lives in a private sync between
your own trusted devices, and the budget goes to full-disk encryption on
each device instead. Keyward never sends a key anywhere: there is no
network code in the engine and the carrier opens no listener. See `AGENTS.md` for the operating rules
(never print values, never commit the vault, collect strays immediately).

## Development

```bash
racket host/main.rkt        # run the app (glaze carrier, native transport)
raco test tests/            # engine tests (store, key metadata, rotation, scan)
racket host/verify.rkt      # real-window self-check: 19-step journey + verdict
raco glaze build --name keyward --entry host/main.rkt --installer   # package
```

- Engine: `racket/backend.rkt` + `racket/core/` (RVT1 contract, `rivet-schema.json`)
- Carrier and UI: `host/` (see [host/README.md](host/README.md)); design tokens in
  `design/prototype/shared.css`

## License

AGPL-3.0
