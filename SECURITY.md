# Security Policy

Keyward is a vault for the release-signing keys of self-updating desktop
apps, so its own security posture is deliberately conservative: the
engine has no network code at all, key values leave the process only
through an explicit clipboard action, and updates are manual by design.
Reports are taken seriously and handled quickly.

## Reporting a vulnerability

Email **security@jrtx.site** (or open a GitHub security advisory on this
repository). Include reproduction steps, affected versions, and your
assessment of impact. You will get an acknowledgment within 72 hours.

Please do not open public issues for security problems.

## Scope

In scope:

- **The vault store** (`racket/core/store.rkt`): the comment-preserving
  INI parser/writer, atomic writes, the 0600 permission tightening, and
  the append-only snapshots under `<folder>/.history/keyward/` that run
  before every mutation. The store is plaintext by design — custody
  relies on device full-disk encryption and a trusted private sync, and
  every surface says so; a report that Keyward silently adds encryption,
  or leaks values outside the documented paths, is a bug.
- **Value exposure paths**: raw key material may leave the process only
  through the explicit `entry-get` / copy-to-clipboard RPC (with an
  exposure disclosure and a 30 s auto-clear). Listings, deep-check and
  scan results must carry names, counts and fingerprints only — a value,
  or a fraction of one, appearing anywhere else is a bug.
- **Update trust policy** (`racket/update-policy.rkt`): the offline trust
  decision — the user-initiated requirement (non-user-initiated checks
  are refused), Ed25519 verification against a pinned public key and
  exact key ID embedded in the application build, the immutable
  release-tag URL requirement, the manifest (1 MiB) and payload
  (512 MiB) size caps, and the rule that Linux package-manager updates
  must carry an explicitly declared deb or rpm format.
- **Key format import and export** (`racket/core/keyformats.rkt`): PEM /
  base64-DER / Sparkle / minisign normalization and export. Values are
  converted, never logged; password-protected minisign secret keys are
  refused, not cracked.
- **The stray-key scanner** (`racket/core/strayscan.rkt`): a report must
  never contain key material — path, line, kind and fingerprint only.
- **The carrier/engine boundary and the RPC surface**: the glaze carrier
  (`host/`) renders and relays; the Racket engine (`racket/backend.rkt`)
  decides. The page reaches the engine only through typed RPC routes, the
  production window runs under a default-deny capability, and the two RPCs
  that answer key values (`entry-get`, `keypair-export`) are not routed to
  the page at all — the carrier calls them itself for the clipboard. The
  carrier uses the native WebView channel (`#:transport 'native`) and the
  engine runs in-process over a pipe pair: no listening network port. Crypto
  or trust decisions sneaking into the page or the carrier are a bug (key
  parsing lives in `racket/core/keymeta.rkt`).
- **Manual-update-only as an intentional exemption**: Keyward is a key
  vault and does not update itself — there is no in-app updater and no code
  path that contacts a network service. Each release publishes a signed
  update feed (`update-manifest.json`, Ed25519, pinned in
  `racket/update-trust.rkt`) for the future user-initiated flow only; any
  code path that downloads or applies an update without explicit user
  action is a critical bug. The rationale is specified in
  [docs/UPDATE-SECURITY.md](docs/UPDATE-SECURITY.md).
- **Signing of the installers themselves**: macOS builds are Developer
  ID-signed and notarized. Windows installers are not Authenticode-signed
  and Linux packages are not vendor-signed for now; verify those against
  `SHA256SUMS` or the Sigstore build attestations.

Out of scope: the security of your sync transport and devices (Keyward
trusts the synced folder you point it at, and full-disk encryption is a
device responsibility), the OS keychains and DPAPI vaults of *other*
family products, social engineering, and physical access attacks.

## Design notes reviewers should know

- The engine has no network code. The only network-adjacent surface is
  the future user-initiated update check, which today exists as the
  pure offline policy module above — it downloads nothing and never
  loads the vault.
- **Plaintext custody is disclosed, not hidden**: the intro, no-vault,
  snapshots and About surfaces on all three hosts state that the vault
  file and its snapshots are plain text on disk. The threat model is a
  trusted private sync between your own devices plus device FDE.
- **Hosts never implement crypto.** Signature checks, public-key
  derivation, fingerprints and pairing decisions live in the Racket
  engine (the `crypto` package's libcrypto factory over the embedded
  runtime); native hosts only carry out clipboard and display steps.
- Clipboard auto-clear is best-effort by platform (change count on
  macOS, marker title on Windows, ownership-marker mime on Linux);
  clipboard history or cloud clipboard sync is explicitly outside
  Keyward's control and disclosed as such.
- Release installers are ad-hoc signed (development signing; not
  notarized) and carry no publisher code signature. Releases publish a
  checked `SHA256SUMS` file, per-asset `.sha256` sidecars, CycloneDX
  SBOMs and Sigstore build-provenance attestations; verify downloads
  with those, not by trusting the installer signature.

## Supported versions

Security fixes land on `main` first and ship with the next tagged
release. During the 0.x preview there is no LTS branch.
