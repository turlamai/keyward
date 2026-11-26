# Keyward

[English](README.md) · **中文**

给「自己会更新的桌面应用」保管发布签名密钥的本地保险库。

[![CI](https://github.com/turlamai/keyward/actions/workflows/ci.yml/badge.svg)](https://github.com/turlamai/keyward/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/turlamai/keyward)](https://github.com/turlamai/keyward/releases)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

凡是走网络自我更新的应用，最终都依赖同一套信任模型：**私钥签更新清单**，
**装进应用里的公钥**验签。Sparkle、Tauri updater、electron-updater、
WinSparkle、Google Omaha——方案都是这一套，而没人替你解决的，从来都是
私钥这一半的日常托管：它存在哪、怎么进 CI、何时轮换，以及怎么在一份
流浪副本抢先*轮换掉你*之前发现它。

> 📖 **第一次接触更新签名？** 阅读双语手册——
> **[使用手册 / Handbook](https://keyward.jrtx.site/guide.html)**（中文原文，
> 附地道英文翻译，可按语言切换）——
> 或[源 markdown](docs/manual.zh-CN.md)：安装、连接保险库、每一项日常操作、
> 接入 CI、发布更新、密钥轮换，为零基础读者写就。

Keyward 是一个守护这些密钥的小型桌面应用。一个 Racket 引擎，后面接一个
Glaze 载体（系统 WebView，macOS / Windows / Linux 共用一套 UI），库文件就放在
你自己的同步盘里，并往上补足明文存储缺的那份纪律：

- **永不显示，只进剪贴板。** 密钥值从不进入界面：复制动作经载体直达
  剪贴板，复制时会明示暴露面（任何应用都能读取剪贴板），并在 30 秒后
  自动清空——期间你自己复制的其他内容永远不会被误删。
- **防丢失。** 每次改动先对存储做快照（同步盘内、只追加）；写入原子化，
  权限收紧。
- **深度校验。** 解析每把密钥（Ed25519 / RSA PKCS#8、base64-DER、
  base64-PEM 或裸 PEM），推导公钥半边，计算指纹，并与存储的公开材料
  配对——过去要靠一堆手工 openssl 命令完成的审计，现在一条命令。
- **收集，不散落。** 应用内生成密钥对直接写入保险库；PEM 导入落成
  单行 base64 值。流浪密钥文件一分钟都不会存在。
- **孤儿检测。** 粘贴坏掉产生的多行残留，打开保险库的瞬间就以行号形式现形。
- **轮换即工作流。** 在 `UPDATE_ED25519_NEXT_*` 名下暂存下一把钥，不动现役
  签名钥；发一个信任它的版本，再 Promote——两阶段 runbook 的机械化。
- **流浪件清查。** 扫描工作区里没入库的私钥散件；命中只报路径、行号与
  指纹，永不显示值。
- **说你的更新器的方言。** Sparkle/minisign 密钥文件直接导入，库内条目
  按原格式复制出去——仅经剪贴板。

保险库格式是纯 INI（`[product]` 小节、`NAME = value`、注释保留），
始终是唯一事实来源——Keyward 是它之上的纪律层，不是锁定。

## 开始使用

AGPL-3.0 许可的免费发布基础设施工具，不接商业激活。 提供 macOS、Windows、Linux 桌面预览。连接真实发布凭据前，先使用可丢弃的合成密钥库。

[安装、首次使用、隐私与备份恢复](docs/USER-GUIDE.zh-CN.md) · [English](docs/USER-GUIDE.md)

## 安装

从 [Releases](https://github.com/turlamai/keyward/releases/latest) 下载：

| 平台 | 下载 | 更新 |
|---|---|---|
| macOS 14+（Apple Silicon 与 Intel） | `keyward-<version>-macos-<arch>.dmg`——`arm64` / `x64`，每种架构另附便携 `.zip` | 仅手动下载——密钥保险库不自我更新（[docs/UPDATE-SECURITY.md](docs/UPDATE-SECURITY.md)） |
| Windows 10+ x64 | `keyward-<version>-windows-x64.msi` 安装器，或 `keyward-<version>-windows-x64.zip` 便携版 | 仅手动下载 |
| Linux x64 / arm64 | `keyward-<version>-linux-x86_64.AppImage` / `keyward-<version>-linux-aarch64.AppImage`、`keyward-<version>-linux-<发行版架构>.deb`、`.rpm`、Flatpak bundle `keyward-<version>-linux-<arch>.flatpak`（app id `site.jrtx.keyward`；`flatpak --user install ./keyward-<version>-linux-<arch>.flatpak` 安装），或便携版 `tar.gz` | 仅手动下载 |

每个发布都带 `SHA256SUMS` 校验清单、CycloneDX
SBOM 与 Sigstore 构建来源证明（`gh attestation verify <file> -R turlamai/keyward`）。

macOS 版本为 Developer ID 签名并公证。**Windows 安装包暂未做 Authenticode
签名**（SmartScreen 首次运行会提示），**Linux 安装包暂未做厂商签名**：请以
`SHA256SUMS` 或构建来源证明校验下载物，不要依赖安装包签名。

## 状态

**Glaze 线的 v0.1.0 已发布**——三个原生宿主（SwiftUI / WinUI 3 / GTK4）
合并为一个载体、一套 UI，发布线从头开始，旧的 0.1.0 – 0.3.0 已下架。
三个桌面的安装包都在
[Releases 页](https://github.com/turlamai/keyward/releases/latest)：
macOS（arm64 / x64，DMG + zip）、Windows（x64，MSI + zip）、
Linux（x64 / arm64，deb + rpm + AppImage + Flatpak + tar.gz）。
两阶段轮换工作流、工作区流浪密钥扫描器、Sparkle/Tauri 密钥格式导入导出
全部保留。载体不监听任何网络端口：页面经进程内通道与引擎通信。

## 安全模型

保险库**有意**保持明文——它活在你自己可信设备间的私有同步里，预算花在
每台设备的全盘加密上。Keyward 从不把密钥发往任何地方：引擎里没有
网络代码，载体也不监听端口。操作守则见 `AGENTS.md`（永不打印值、永不提交保险库、
流浪件立即收集）。

## 开发

```bash
racket host/main.rkt        # 运行应用（glaze 载体，原生通道）
raco test tests/            # 引擎测试（存储、密钥元数据、轮换、扫描）
racket host/verify.rkt      # 真实窗口自检：19 步走查 + 判定
raco glaze build --name keyward --entry host/main.rkt --installer   # 打包
```

- 引擎：`racket/backend.rkt` + `racket/core/`（RVT1 契约，`rivet-schema.json`）
- 载体与 UI：`host/`（见 [host/README.md](host/README.md)）；设计 token 在
  `design/prototype/shared.css`

## License

AGPL-3.0
