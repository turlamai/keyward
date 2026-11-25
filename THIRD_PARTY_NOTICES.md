# Third-party notices

Keyward builds on the components below. Each entry names where the
component enters the shipped artifacts and the license it is distributed
under; consult the upstream license files for full terms. This file is
the root overview for the repository; the generated per-build notice and
SBOM bodies stay in CI artifacts, so this document is the authoritative
notices record for every published release. The Rivet toolchain is a
first-party TurLamAI project (MIT) consumed as a pinned package — not
third-party code — so it is not listed here.

## Racket CS runtime

Every platform host embeds the statically linked Racket CS runtime
([racket/racket](https://github.com/racket/racket), 9.x). Racket is
distributed under the MIT license and the Apache License 2.0, at your
option; the Racket CS runtime system additionally embeds Chez Scheme,
distributed under the Apache License 2.0 (per Racket's `LICENSE.txt`).

## crypto-lib

Key work — Ed25519 public-key derivation, key parsing and the crypto
primitives behind Deep Check and the update trust policy — runs through
the Racket `crypto` package's libcrypto factory
([racket/crypto](https://github.com/racket/crypto)), distributed under
the Apache License 2.0. It links against the platform's OpenSSL
(libcrypto), which ships with the operating system.

## WebKitGTK, GTK 3 and GLib

On Linux the glaze carrier renders its UI in WebKitGTK 4.1 (GTK 3), using
the system libraries. WebKitGTK is licensed under the GNU Lesser General
Public License version 2.0 or later; GTK and GLib under the GNU Lesser
General Public License version 2.1 or later. Depending on the Linux install
shape they come from two places:

- deb / rpm / tar.gz / Flatpak: WebKitGTK 4.1 and GTK 3 are supplied by
  the distribution (or by you, for the tarball; the Flatpak bundles the GNOME
  runtime).
- `.AppImage` artifacts: the AppImage carries the WebKitGTK/GTK dependency
  closure bundled by the glaze release toolchain.

## Microsoft WebView2 runtime (Windows)

On Windows the carrier renders its UI in the Microsoft Edge WebView2
runtime, provided by Microsoft under the Microsoft Edge WebView2 terms and
shipped with the operating system.

## Apple WebKit (macOS)

On macOS the carrier renders its UI with WKWebView, provided under Apple's
SDK license terms and shipped by the operating system itself.

## AppImageKit runtime (`.AppImage` artifacts)

`.AppImage` release artifacts contain the type-2 AppImage runtime from
[AppImage/AppImageKit](https://github.com/AppImage/AppImageKit),
licensed MIT. The build tool is the official `appimagetool` 1.9.0
release pinned by the Rivet release toolchain, run in
extract-and-run mode by the release workflow. AppImageKit's license
does not apply to the contents of the AppImage: those are Keyward's
AGPL-3.0 payload plus the entries above.
