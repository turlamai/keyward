# host/ — glaze carrier

Keyward's desktop UI runs on **glaze** (system WebView + HTML/CSS/JS UI) per the owner
decision of 2026-11-23 (keyward#34: re-line from rivet to glaze). This directory is the
carrier: the Racket process that opens the native window, serves the web UI and exposes
the typed RPC surface to the page. The native hosts (`macos-host/`, `windows/`, `linux/`)
are retired.

| Path | Role |
|---|---|
| `main.rkt` | Carrier entry. `api` is the route list `glaze.rktd` points at; `raco glaze schema write` regenerates `glaze-schema.json` from it. |
| `verify.rkt` | Real-window self-check (typed report in `.glaze/verify/`). Run on every declared platform. |
| `linux-verify.sh` | Headless Linux CI wrapper (session bus on `/run/user`, Xvfb). |
| `netcheck.rkt` | Listening-socket probe of this process (zero-network evidence). |
| `e2e-config.rkt` | Points the harness at a disposable config dir and vault. Must load before the engine. |
| `web/index.html` + `app.js` | The product UI, evolved from the landed prototype (`design/prototype/app.js`). Tokens come single-source from `design/prototype/shared.css`, copied into the runtime public dir at startup. |
| `web/e2e.js` | In-page product journey; inert unless the carrier runs with `KEYWARD_E2E=1` / `KEYWARD_SELFTEST=1`. |

## Surface

- **Engine**: 17 page RPCs of `rivet-schema.json` over `rivet/bridge` (in-process RVT1
  pipe pair). The two RPCs that answer key values (`entry-get`, `keypair-export`) are
  **carrier-only**: the page cannot reach them, and `scripts/check-rpc-surface.py` fails
  if one is ever routed.
- **Carrier routes**: `api/host/context`, `api/host/copy` (value → clipboard inside the
  carrier, 30 s auto-clear that only erases what this action put there),
  `api/host/clipboard` (state only), the native open panel (`api/dialog/open`) and the
  harness routes (`api/host/e2e*`).
- **Transport**: `#:transport 'native` by default — no listening socket. `KEYWARD_TRANSPORT=http`
  falls back to the loopback HTTP adapter for development.
- **Capability**: the production window runs under `host-capability` (`rpc host
  clipboard dialog:open e2e`), default-deny. `scripts/check-route-permissions.py` makes a
  missing class or an unused grant a static failure.

## Self-check

```bash
racket host/verify.rkt                       # real window, 19-step journey, verdict + report
KEYWARD_SELFTEST=1 racket host/main.rkt      # the same journey on the production carrier
bash host/linux-verify.sh                    # headless Linux (Xvfb + session bus)
KEYWARD_SHOT=/tmp/shot.png racket host/verify.rkt   # optional window capture (not on Linux)
```

The verdict covers: window booted, report delivered, every step ok, step count, and
`no-listener` (the process has no listening TCP socket). `KEYWARD_SELFTEST_TIMEOUT_MS`
shortens the wait while debugging; `KEYWARD_TRACE=1` prints every RPC the carrier serves.

## Production path vs the verifier

`host/verify.rkt` runs **without** a capability (open-route mode). The production carrier
(`racket host/main.rkt`, the package) runs under `host-capability`, where glaze is
default-deny: a route without a `#:permission` class, or with a class that is not
granted, is refused. Only the packaged self-check exercises this path (`packaged-smoke.yml`
runs `KEYWARD_SELFTEST=1` on the packaged program), so run it after touching routes or
the capability.

## Harness

Routes under `api/host/e2e*` are inert unless `KEYWARD_E2E=1`. With the gate on the page
asks the carrier at start-up (`e2e` in `api/host/context`) and runs the journey on the
first load against a disposable vault; the fixtures answer paths and booleans only.
`api/host/e2e-reset` rotates the fixtures and clears the report.
