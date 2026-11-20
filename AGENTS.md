# Rivet agent contract

## 家族设计（必读入口）

- 设计/UI 任务先加载 `tlai-product`，必读 `references/policy.md` 与 `references/design-standard.md`（理念、决策规则、UI 验收）。技能缺失时读取 ZCode 真源：macOS/Linux `~/Sync/ZCode/skills/tlai-product/`；Windows `D:/ZCode/skills/tlai-product/`。无法读取须报告规范未核验，不凭记忆跳过。
- 家族规范管共性；本仓现有设计、行为与 token 真源管具体值和产品差异。例外记回原契约，不复制家族规则或新增数值表；已有界面按下一次相关切片渐进对齐。
- 改界面先改原型、落账后实现；按家族 UI 清单与本仓当前技术线的既有门禁验收，原型对照和真实交互证据都要保留；对外宣传使用验收后的实物截图。

## 实现路由（agent 按任务读真源）

- 实现界面以 `design/prototype/` 为准：对照 HTML/CSS/JS 与实物截图验收，不依赖散文复述。
- Token/几何值真源 = `design/prototype/shared.css`（亮暗成对；无 shared.css 的仓 = design/prototype/ 各页样式）；`design/DESIGN.md` 只记语义名、用途与决策。
- 行为边界与跨平台一致性以 `design/DESIGN.md` 的不变式与平台差异节为准。
- 改界面先改原型再改实现（tlai-product）；动共享层（design/、shared/）先 issue 声明，同 commit 落契约。

## Current owner decision — 2026-11-18 quality-first

This product is in **non-commercial development**. The prior 2026-10/11 product pricing, trial, paid-feature, Free/Pro and family Permit/Commerce rollout decisions are canceled. Do not introduce checkout, subscriptions, activation, commercial entitlement, paid update windows or a paywall. Do not change source-license terms or release signing and identity verification. Prioritize product correctness, reliable native experience, recovery, bilingual README and truthful website claims. The [current family portfolio](https://github.com/turlamai/turlamai.github.io/blob/master/PORTFOLIO.md) governs every slice.

## Required policy discovery at each slice

Before starting the next bounded slice, refresh remote state safely and re-read
this root AGENTS file, the repository's canonical implementation handoff, and
the current [family delivery standard](https://github.com/turlamai/turlamai.github.io/blob/master/docs/PRODUCT-STANDARD.md),
[documentation language policy](https://github.com/turlamai/turlamai.github.io/blob/master/docs/DOCUMENTATION-LANGUAGES.md)
and [portfolio decisions](https://github.com/turlamai/turlamai.github.io/blob/master/PORTFOLIO.md).
Follow the corresponding Chinese links when preferred; both public user paths
must express the same promises. Product-specific plans and technical protocol
owners remain in their owning repositories.

Record the repository starting SHA and the central-policy commit/revision
actually read in the PR or handoff. A link's presence is not an acknowledgement
that an agent has read it. Existing conversations and stale checkouts do not
receive policy updates automatically: refresh these inputs at slice boundaries.
Preserve other agents' dirty worktrees; use an isolated checkout when needed,
without stashing, resetting or overwriting their work. Missing/offline policy
inputs must be reported as unverified, not silently claimed current.


Human-first. Agent-native. Local by design.

## Start every task here

```bash
raco rivet inspect --json
raco rivet doctor --json
```

`inspect` is the machine-readable project map. It identifies the shared Racket
backend, each native UI edit point, platform maturity, generated directories,
and safe lifecycle commands. `doctor` reports the exact local toolchain and
returns a failing exit status when the current host is not usable.

## Architecture boundary

- Keep shared application and domain logic in `racket/backend.rkt`.
- Keep Windows UI native in WinUI 3 / C++/WinRT under `windows/`.
- Keep macOS UI native in SwiftUI/AppKit under `macos-host/`.
- Keep Linux UI native in GTK4 under `linux/`.
- Do not introduce a cross-platform UI DSL or bypass RVT1 with an ad-hoc IPC.
- iOS/iPadOS/watchOS and Android are foundation targets until their
  generated app, embedding, packaging, signing, and device workflows exist.

## Capability sourcing

When a feature is not already present, do not reject Racket or add another
runtime by reflex. Read `capability-sourcing` from `inspect --json`, then choose
the narrowest boundary that fits:

1. Prefer a Racket built-in or maintained package. Discover candidates with
   `raco docs <term>`, `raco pkg show`, and
   `raco pkg catalog-show --all --only-names`; inspect a candidate with
   `raco pkg catalog-show --modules <package>`.
2. Put UI, lifecycle, accessibility, notification, device, and other
   platform-owned behavior in the first-party native host.
3. Use FFI for a stable C ABI that needs frequent, low-latency in-process
   calls. Hide `ffi/unsafe` behind a small safe module with explicit ownership,
   callback, thread, ABI, and native-library packaging rules.
4. Use `subprocess` or `system*` for a mature executable doing coarse-grained
   work. Pass an executable and argv directly; never construct a shell command.
   Add a version probe, timeout, bounded/concurrently drained output, exit-code
   handling, cancellation, packaging, and license checks.
5. Use a sidecar only for a persistent runtime, streaming workload, unstable
   ABI, or required crash isolation. Own authentication, protocol versioning,
   resource limits, restart/shutdown, packaging, and offline behavior.
6. Implement the capability only when it is small or security-critical and
   owning it is cheaper than owning the dependency boundary.

For every choice, verify Racket 9.0 CS support, license/redistribution terms,
all target OS/architectures, upstream maintenance, reproducible installation,
failure behavior, packaged dependency closure, and a clean-machine smoke test.

## Ownership

Source you may edit:

- `racket/`
- `windows/`
- `macos-host/`
- `linux/`
- `rivet.rktd`
- `rivet-schema.json` when an API compatibility break is intentional
- declared application resources

Generated output you should not hand-edit:

- `windows/GeneratedBackend.hpp`
- `macos-host/Sources/RivetHost/GeneratedBackend.swift`
- `linux/GeneratedBackend.hpp`
- `.rivet/`
- `build/`
- `dist/`
- `windows/Generated Files/`
- `windows/obj/`
- `windows/RivetHost/`
- `macos-host/.build/`

`raco rivet build` regenerates the typed clients. Use `raco rivet clean` to
remove transient build output while keeping the generated client sources that
make the native API reviewable.

## Verification loop

This project includes a source-controlled `rivet-schema.json` API baseline.
Refresh it only after deliberately changing the public backend schema:

```bash
raco rivet schema --output rivet-schema.json
```

Before accepting later API changes, run the compatibility gate. Adding a new
RPC, Event, State, Record, or Enum type is compatible; removing one or changing
a type, argument order, result, Record field/order, or an existing Enum's
cases/order is breaking:

```bash
raco rivet schema check rivet-schema.json --json
```

```bash
raco rivet build
raco rivet dev
raco rivet package
raco rivet verify
```

Pull-request CI must run `raco rivet build` for the Windows, macOS, and Linux
hosts on the same runner image classes used for release. A release job must not
be the first place native source is compiled. Follow Rivet's native-host CI
guide: https://github.com/turlamai/rivet/blob/main/docs/ci.md

After changing RPC, Event, State, Record, or Enum declarations, run the
compatibility gate and rebuild before editing code that consumes generated native APIs.
Update the baseline only when a breaking change is intentional and governed by
the application's release policy. Preserve the first `rivet: error:` line and
nearby compiler output when diagnosing a failure.
## Keyward operating rules (product-specific, override nothing above)

- **Never print a key value.** Values travel backend → clipboard only
  (`entry-get` exists for that single purpose). Listing/check RPCs carry
  names, counts, and fingerprints exclusively — keep it that way; a
  `~a` of the wrong struct in a log line is an incident.
- **The vault is the user's synced INI file.** Keyward is a discipline
  layer over `~/Sync/Keys/secrets.ini`, not a new format and not a
  service. No network code in the engine, ever.
- **Every mutation snapshots first** (`store-snapshot!` before any write);
  writes are atomic (tmp + rename) and end at permission 600.
- **Single-line values are a hard invariant.** `store-set-entry!` rejects
  newlines; multi-line residue must surface as orphan line numbers.
- **Collect, don't scatter.** Generation/import paths write into the vault
  directly; a key file may exist transiently only inside the generation
  call frame.
- The Keys folder itself has its own manual (`~/Sync/Keys/AGENTS.md`) —
  boundary there: product signing keys only, no API tokens.

## 组合定位（Portfolio placement）

2026-11-18 起，以产品交付质量为目标，不推进收费版、试用、商业授权或结账。既有 LICENSE 和发行签名验证保持不变。当前权威是[产品组合策略](https://github.com/turlamai/turlamai.github.io/blob/master/PORTFOLIO.zh-CN.md)。

## 产品交付与下一步（2026-11-18）

请以当前代码与验收证据推进用户主流程、恢复、跨平台原生体验、签名更新、文档和产品主页，不按任何历史商业规划开发。

## Public product documentation

The paired `docs/USER-GUIDE.md` / `docs/USER-GUIDE.zh-CN.md` own the public installation, first-use, data/recovery, privacy and availability path. Keep the homepage and both README entry points aligned with them when behavior changes. Detailed technical contracts and the current implementation queue retain their existing owners. Do not publish target prices, a purchase link or a ready/secure/platform claim before its release evidence exists.
