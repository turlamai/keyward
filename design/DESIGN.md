# Keyward DESIGN.md — 视觉与交互契约

原型（`design/prototype/`）与实现（`macos-host/` · `windows/` · `linux/`）都遵循本文件的语义、不变式与平台差异；**数值不在此复制**。

**真源分工**：颜色、字体栈、字号、几何与动效时长的具体值以 `design/prototype/shared.css` 为唯一真源（亮暗成对）；本文件只记语义名、用途与决策。改值改 CSS，改语义改本文件。产品站 `site/styles.css` 与原型同源；站点与 app 的微小差异以 app 为准。

## Brief（2026-11-11）

- **产品现状**：v0.3.0 已发布，三平台原生 UI（SwiftUI / WinUI 3 / GTK4）已建成并共享同一交互契约（相同的状态刷新、对话框默认与剪贴板披露）。**本契约性质 = 既有打磨，不是从零设计**：暖纸色 token 体系已落地，原型做的是 HIG 级收敛、状态全覆盖与后续 UI 切片的评审介质。视觉契约不受商业/定价决策影响，商业/定价 UI 不进原型。
- **目标**：把「保密即界面」做成视觉语言——值永不显示、复制必披露、破坏必确认；让两阶段轮换（Stage → Promote）这个差异化工作流在界面上自己会走；界面达到可直接用于官网宣传的质量。
- **原型范围**（5 屏 × 亮/暗）：① 主视图（英雄屏：概览 tiles + 产品详情 header + Rotation 进行态 + Entries 全状态）② 首启空态（No vault selected + 信任文案）③ 轮换确认（Promote 危险操作对话框 + 安全默认）④ 快照浮层（loss protection + Restore）⑤ 散钥扫描浮层（告警态：路径/行号/指纹，永不显示值）。
  - **设置屏不在范围**：产品真实信息架构没有设置面——保险库选择走系统文件对话框（⌘O）、主题跟随系统、引擎零网络故无配置项；原型如实反映现有 IA，不为原型虚构产品没有的屏幕。
- **Exit 条件**：5 屏关键状态齐（空态：屏②与 Entries/空节；告警态：屏⑤与 empty/empty:2 状态；进行态：轮换 Phase 1）+ 交互逻辑定稿 + HIG 清单全过 + 用户评审通过；验收后实物截图才能作对外素材。
- **不在范围**：新功能、RVT1 契约变更（不动 `rivet-schema.json` / `app/backend.rkt`）、商业/定价 UI、新配色体系。

## 设计原则（HIG 内核）

- **保密即界面**：界面上不存在「值」——listing 只载名字、数量、指纹；值唯一出口是 Copy 动作（`entry-get` 只为此存在）。原型自身也不渲染任何密钥值或占位符。
- **暴露必披露**：每次复制状态栏即时宣告（任何应用可读剪贴板）并倒计时自动清除；后台清除同样播报。永不静默。
- **状态即安全**：ok / warn / neutral / empty 四态语义贯穿侧栏圆点、徽标与 chip；每个 entry 独立判定，一个坏 key 不被同节好 key 掩盖（多 key 节按名字标注逐个指纹）。
- **防错一致**：Generate / Stage / Promote / Discard / Delete 全部确认对话框；**Return 永远落在 Cancel**（安全动作拿视觉主位），破坏性动作需显式点击；删除文案先讲条目用途（purpose 提示），再讲可恢复（快照先行）。
- **层级克制**：bg < sidebar/surface < badge 三层表面足够；饱和色只上 glyph 与主按钮，选中/悬停是 quiet fill；边框不随状态变色（唯一许可例外：EntryCard 悬停描边——复制的唯一入口需要引导）。

## Tokens（语义名与用途；值见 `shared.css`）

| Token | 用途 |
|---|---|
| `--bg` | 画布 |
| `--sidebar` | 侧栏/状态栏底 |
| `--surface` | 卡片/浮层 |
| `--line` | 分隔/描边 |
| `--ink` / `--ink-2` / `--ink-3` | 主文字 / 次级文字 / 辅助文字与占位（低对比的 ink-3 不用于说明文字） |
| `--accent` | 品牌 glyph/主按钮/Copy 入口 |
| `--accent-soft` | accent 弱底 |
| `--selection` / `--hover` | 选中 / 悬停 quiet fill（由 accent 按透明度派生） |
| `--badge` | KVChip/徽标底 |
| `--ok` / `--warn` / `--neutral` | 配对通过 / 注意·空值·破坏性 / 空节·无键 |

- **字体角色**：界面用系统 sans 栈；产品名标题、pane 标题、按钮、条目标识符、次级各有字号层级（见 CSS）。**entry 名、指纹、路径、时间戳一律 mono**——标识符与正文不同字形是这产品可扫读性的关键。
- **几何与动效**：侧栏宽度（中/窄窗口自适应，窄窗口收敛为顶部产品选择）、圆角、间距节奏（4/8/12/16/20）与动效均以 CSS 为准；遵循 prefers-reduced-motion。
- **语言**：界面文案英文（三平台现状 UI 语言）；本文件中文，新增代码注释英文。图标一律内联 SVG，不用位图。

## 组件词汇

`Sidebar`（brand + SummaryTile×4 + ProductRow 列表）· `ProductHeader`（KVChip 组 + StatusChip + Deep Check/Snapshots 入口）· `RotationCard`（两阶段 runbook：Stage → Promote，Promote 由 paired 状态 gate）· `EntryCard`（lock glyph + mono 名 + purpose 提示 + Copy / Copy as… / Import / Delete）· `ConfirmDialog`（安全默认 + 用途披露）· `SnapshotsSheet`（快照列表 + Restore）· `StrayScanSheet`（路径/行号/指纹，永不显示值）· `StatusBar`（披露行 + vault 路径）。

## 不变式

1. **值不上屏**：任何界面元素不得渲染密钥值或其占位；指纹（SHA-256 前 16 hex）、计数、key id 是唯一允许的派生标识。
2. `accent` 只用于：品牌 glyph、主按钮（含对话框安全默认位）、Copy 入口、聚焦态；`ok`/`warn`/`neutral` 只用于状态语义；禁止大面积色块。
3. 层级靠 `surface`/`badge` 填充与 `line` 分隔表达，不堆阴影、不用重描边；边框颜色不随状态变化（EntryCard 悬停描边为唯一许可例外）。
4. 亮暗主题成对设计（双主题均验证态），不存在只有暗态的界面。
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

## 本轮原型优化（2026-11-14）

本节更新本项目的设计基线；上文引用的宿主路径与历史已验证状态属于既有记录，不代表本轮已核对宿主实现。本轮仅修改 OpenDesign 原型，未修改引擎或三平台宿主。

### 入口与范围

- `index.html` 直接进入主视图，取代单独的评审链接列表；侧栏提供 Snapshots、Scan for stray keys 与 Choose vault 入口。
- `prototype/main.html` 保留主视图独立入口。
- `prototype/onboarding.html` 为未选择保险库状态，可打开示例保险库。
- `prototype/rotation.html` 直接进入 Promote 确认。
- `prototype/snapshots.html` 与 `prototype/stray-scan.html` 直接进入相应对话框，关闭后返回同一应用。
- 五个入口共用 `prototype/shared.css` 与 `prototype/app.js`，不再复制背景结构与状态逻辑。
- 无设置页、定价页、平台切换或设计演示控制面板。英文产品文案保留。

### 视觉方向与可读性

延续暖纸色、陶土色、系统字体与等宽标识符，以更明确的标题、正常流排版和分隔线整理信息。品牌背景是既有契约的延续；此选择并非新增通用配色方案。

原型采用以下可读性修订（品牌 glyph 底色、操作与聚焦、次级/辅助文字、分隔线、成功/告警文字各成对定义，值见 `shared.css`），后续宿主实现需对齐；不将低对比色用于说明文字。明暗模式跟随系统，无产品内主题切换。尺寸与动作色集中定义；不使用渐变背景、装饰阴影堆叠或静态伪悬停。

主层级为产品标题 → Active key 元信息 → 两阶段轮换指引 → Entries。产品侧栏同时显示状态文字与状态点。概览保留产品数、配对数、需注意产品数；快照移至独立操作入口，条目数由实际示例条目计算，不沿用硬编码条数。

### 唯一轮换顺序

1. Stage：保留当前签名密钥，准备并检查 next pair。
2. 发布信任：将 next public anchors 放入应用，使用旧密钥签名并发布 phase-1 release。
3. 该版本发布后，将 CI signing secret 切换到 staged private key。
4. Promote：用户明确确认发布与 CI 交接均已完成后，替换 active entries 并清理 NEXT entries。

Pairing 通过只是 Promote 的条件之一，不能代表外部版本已经发布或 CI 已更新。确认框分别收集这两项交接确认；界面不声称自动验证外部系统。每次状态变更先保存可恢复的示例快照。

### 原型行为边界

- 页面明确标识 Interactive prototype / sample data。没有真实密钥值，也不生成、导入或复制真实密钥。
- Choose vault 打开明确披露的示例数据，不伪造系统文件选择器；无文件系统读写。
- Copy 只模拟披露与 30 秒有效期；未点击时不显示已复制，不写剪贴板，不承诺清除用户真实剪贴板，到零不循环。生产实现仍须遵守真实复制披露与清除规则。
- Deep Check 有处理中与结果反馈，但只检查示例元信息；结果明确说明未执行密码学验证。
- Stage / Promote / Discard / Delete / Restore 使用原生模态确认；Cancel 默认聚焦，Return 取消，Escape 关闭。Promote 需已配对并逐项确认发布与 CI 交接。
- Add / Import 只录入条目名称和用途。Add 创建空值元信息；Import 用示例状态代替真实材料导入，不提供真实密钥输入框。名称校验要求大写字母开头、只含大写字母/数字/下划线，且同产品唯一。
- 所有变更共享内存状态；产品列表、条目计数、注意状态及快照一起更新。恢复会替换整个示例保险库，并先保存恢复前状态。
- 扫描只呈现三条固定示例发现，明确说明未访问文件夹；只显示路径、行号、类型与指纹。
- 刷新或在不同独立入口重新打开会重置示例状态；不承诺持久化。

### 键盘与窗口

- 可见聚焦样式；按钮均为真实语义控件，Copy 常驻，不依赖悬停。
- Cmd/Ctrl+O 打开保险库选择说明；Cmd/Ctrl+R 运行示例检查；Cmd/Ctrl+L 打开快照。
- 关闭或变更后焦点返回可用控制，筛选导致条目消失时回到主操作。
- 大窗口侧栏；窄窗口使用顶部产品选择。各宽度段按内容重排，不缩放整页，不添加移动端设备壳。
- 对话框提供关闭入口，正文自然换行，条目详情完整显示名称和用途。输入错误仅在提交失败后出现。

### 交付状态

本轮写入可编辑源文件与交互逻辑；未运行浏览器预览、截图或自动验收，未宣称达成原 Exit 条件中的用户评审通过。真实文件操作、密码学行为、剪贴板托管及三平台实现一致性仍须在产品实现阶段验证。
