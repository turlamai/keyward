# Keyward DESIGN.md — 视觉与交互契约（单一真源）

原型（`design/prototype/`）与实现（`macos-host/` · `windows/` · `linux/`）都遵循本文件；改视觉先改这里，再同步三平台实现。
Tokens 1:1 提取自 `macos-host/Sources/RivetHost/Theme.swift`（三平台共享的 family token 结构，亮暗两态均为 ThemeState 已验证状态）；产品站 `site/styles.css` 与之同源（bg/accent/line 一致，站点 `--line` 暗值 `#35322d` 与 app `#3a362f` 的微差以 app 为准）。表中唯一的非 Theme.swift 项是 `--accent-soft`，取自产品站同源暖色（app 端其职责由 selection/hover/badge 覆盖，原型保留备用）。

## Brief（2026-11-11）

- **产品现状**：v0.3.0 已发布，三平台原生 UI（SwiftUI / WinUI 3 / GTK4）已建成并共享同一交互契约（相同的状态刷新、对话框默认与剪贴板披露）。**本契约性质 = 既有打磨，不是从零设计**：暖纸色 token 体系已在 Theme.swift 落地，原型做的是 HIG 级收敛、状态全覆盖与后续 UI 切片的评审介质。2026-11-10 产品从免费基础设施重分类为商业方向、定价未定——视觉契约不受影响，商业/定价 UI 不进原型（授权与价格口径以 PORTFOLIO.md / PRICING.md 权威档更新为准，本仓 AGENTS.md 组合定位节尚未同步，以权威档为准）。
- **目标**：把「保密即界面」做成视觉语言——值永不显示、复制必披露、破坏必确认；让两阶段轮换（Stage → Promote）这个差异化工作流在界面上自己会走；界面达到可直接用于官网宣传的质量。
- **原型范围**（5 屏 × 亮/暗）：① 主视图（英雄屏：概览 tiles + 产品详情 header + Rotation 进行态 + Entries 全状态）② 首启空态（No vault selected + 信任文案）③ 轮换确认（Promote 危险操作对话框 + 安全默认）④ 快照浮层（loss protection + Restore）⑤ 散钥扫描浮层（告警态：路径/行号/指纹，永不显示值）。
  - **设置屏不在范围**：产品真实信息架构没有设置面——保险库选择走系统文件对话框（⌘O）、主题跟随系统、引擎零网络故无配置项；原型如实反映现有 IA，不为原型虚构产品没有的屏幕。
- **Exit 条件**：5 屏关键状态齐（空态：屏②与 Entries/空节；告警态：屏⑤与 empty/empty:2 状态；进行态：轮换 Phase 1）+ 交互逻辑定稿 + HIG 清单全过 + 用户评审通过；验收后实物截图才能作对外素材。
- **不在范围**：新功能、RVT1 契约变更（不动 `rivet-schema.json` / `racket/backend.rkt`）、商业/定价 UI、新配色体系。

## 设计原则（HIG 内核）

- **保密即界面**：界面上不存在「值」——listing 只载名字、数量、指纹；值唯一出口是 Copy 动作（`entry-get` 只为此存在）。原型自身也不渲染任何密钥值或占位符。
- **暴露必披露**：每次复制状态栏即时宣告（任何应用可读剪贴板）并倒计时 30 s 自动清除；后台清除同样播报。永不静默。
- **状态即安全**：ok / warn / neutral / empty 四态语义贯穿侧栏圆点、徽标与 chip；每个 entry 独立判定，一个坏 key 不被同节好 key 掩盖（多 key 节按名字标注逐个指纹）。
- **防错一致**：Generate / Stage / Promote / Discard / Delete 全部确认对话框；**Return 永远落在 Cancel**（安全动作拿视觉主位），破坏性动作需显式点击；删除文案先讲条目用途（purpose 提示），再讲可恢复（快照先行）。
- **层级克制**：bg < sidebar/surface < badge 三层表面足够；饱和色只上 glyph 与主按钮，选中/悬停是 quiet fill；边框不随状态变色（唯一许可例外：EntryCard 悬停描边——复制的唯一入口需要引导）。

## Tokens（与实现 1:1）

| Token | Light | Dark | 用途 |
|---|---|---|---|
| `--bg` | `#faf7f2` | `#1b1a18` | 画布 |
| `--sidebar` | `#f3eee6` | `#24221f` | 侧栏/状态栏底 |
| `--surface` | `#ffffff` | `#2e2b27` | 卡片/浮层 |
| `--line` | `#e8e2d9` | `#3a362f` | 分隔/描边 |
| `--ink` | `#241f1b` | `#ece9e2` | 主文字 |
| `--ink-2` | `#6b6660` | `#a6a099` | 次级文字 |
| `--ink-3` | `#a8a099` | `#6b6660` | 辅助文字/占位 |
| `--accent` | `#c15f3c` | `#d08a6e` | 品牌 glyph/主按钮/Copy 入口 |
| `--accent-soft` | `#f7e5dd` | `#3a2d27` | accent 弱底 |
| `--selection` | accent @10% | accent @16% | 选中 quiet fill |
| `--hover` | accent @6% | accent @10% | 悬停 quiet fill |
| `--badge` | `#f0ebe2` | `#3a362f` | KVChip/徽标底 |
| `--ok` | `#2e7d32` | `#81c784` | 配对/检查通过 |
| `--warn` | `#b26a00` | `#ffb74d` | 注意/空值/破坏性 |
| `--neutral` | `#8e8e93` | `#98989e` | 空节/无键 |

- **字体**：`system-ui, -apple-system, "Segoe UI", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei"`；正文 13px/1.5，产品名标题 22px/700，pane 标题 17px，次级 12px，辅助 10–11px；**entry 名、指纹、路径、时间戳一律 mono**（`ui-monospace, SFMono-Regular, Menlo, Consolas`）——标识符与正文不同字形是这产品可扫读性的关键。
- **几何**：侧栏 280px · 状态栏 28px（Theme.swift 实测值）；详情大卡圆角 14px · 卡片/控件 8px · chip 6px。**间距节奏**：4/8/12/16/20。**动效**：120ms easeOut，不过度。
- **语言**：界面文案英文（三平台现状 UI 语言）；本文件与原型注释中文。图标一律内联 SVG，不用位图。

## 组件词汇

`Sidebar`（brand + SummaryTile×4 + ProductRow 列表）· `ProductHeader`（KVChip 组 + StatusChip + Deep Check/Snapshots 入口）· `RotationCard`（两阶段 runbook：Stage → Promote，Promote 由 paired 状态 gate）· `EntryCard`（lock glyph + mono 名 + purpose 提示 + Copy / Copy as… / Import / Delete）· `ConfirmDialog`（安全默认 + 用途披露）· `SnapshotsSheet`（快照列表 + Restore）· `StrayScanSheet`（路径/行号/指纹，永不显示值）· `StatusBar`（披露行 + vault 路径）。

## 不变式

1. **值不上屏**：任何界面元素不得渲染密钥值或其占位；指纹（SHA-256 前 16 hex）、计数、key id 是唯一允许的派生标识。
2. `accent` 只用于：品牌 glyph、主按钮（含对话框安全默认位）、Copy 入口、聚焦态；`ok`/`warn`/`neutral` 只用于状态语义；禁止大面积色块。
3. 层级靠 `surface`/`badge` 填充与 `line` 分隔表达，不堆阴影、不用重描边；边框颜色不随状态变化（EntryCard 悬停描边为唯一许可例外）。
4. 亮暗主题成对设计（ThemeState 双主题均验证态），不存在只有暗态的界面。
5. 破坏性操作（Generate / Stage / Promote / Discard / Delete）必经确认对话框且 Return 落 Cancel；每次变更先快照，对话框文案必须说明后果与可恢复路径。
6. 键盘可达：⌘O 选择保险库、⌘R Deep Check、⌘L 快照；对话框安全默认；鼠标不可用时可完整操作。


## 平台映射与差异声明（预钉 · 宿主实现时升级为落点表）

统一层（三平台必须一致，`design/prototype/` 原型已锁定）：信息架构、核心流程、快捷键语义、
语义色与层级词汇。因地制宜层（按平台惯例落地，不预画像素）：

| 维度 | macOS | Windows | Linux |
|---|---|---|---|
| 修饰键 | ⌘ | Ctrl | Ctrl |
| 命令入口 | 原生菜单栏 | 菜单栏/命令行内 | 菜单栏 |
| 字体 | 系统栈 + PingFang SC | 系统栈 + Microsoft YaHei | 系统栈 + Noto Sans CJK |
| 原生控件 | SwiftUI 控件 | WinUI 3 控件 | GTK4 控件 |

差异声明纪律：宿主特例必须先写进本节才能实现；未声明的宿主差异按违约处理
（案例：taskly 漂移台账 D8）。
