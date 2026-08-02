# 更新日志 / Changelog

本文件记录 AgentAwake 的重要变更。
后续开发时，先把改动写入 **Unreleased / 未发布**；
正式发布时，再将对应条目移动到带版本号和日期的新章节。

This file records notable changes to AgentAwake.
Add ongoing work under **Unreleased** first, then move those entries into a
dated version section when a release is published.

版本号遵循 [Semantic Versioning](https://semver.org/)。
Version numbers follow [Semantic Versioning](https://semver.org/).

## [Unreleased / 未发布]

### Planned / 计划

- 下一阶段将按 OpenCode、Cursor、Cline/Kilo Code、Kimi/Qwen 的顺序，逐个研究并
  验证第三方零配置适配器；在完成资源、隐私与生命周期验收前不宣称自动支持。
  The next phase will research and verify zero-setup adapters one by one,
  starting with OpenCode, Cursor, Cline/Kilo Code, and Kimi/Qwen. Automatic
  support will not be claimed before resource, privacy, and lifecycle checks.

## [0.5.0] - 2026-08-02

### Added / 新增

- 倒计时自然结束或最后一个 Agent 确认停止时，播放原创的“星眠”完成音；
  设置中可关闭或试听，手动关闭与退出不会触发。
  Play the original “Star Sleep” completion sound when a timer expires or the
  last Agent is confirmed stopped. Settings can disable or preview it; manual
  shutdown and app exit stay silent.
- 可扩展的 Provider 身份、适配器解析规则、统一活动来源与置信度模型，并兼容旧版
  Codex/Claude 租约。
  Extensible provider identities, adapter-owned parsing rules, unified activity
  sources and confidence, with legacy Codex/Claude lease compatibility.
- 自定义 Agent Bridge：一次性 helper 支持 `start`、`heartbeat`、`stop`，
  设置页可安装、修复、移除并复制命令模板。
  A custom Agent Bridge whose one-shot helper supports `start`, `heartbeat`,
  and `stop`, with install, repair, removal, and command copying in Settings.
- 可重复的 RSS、CPU、线程与文件句柄采样脚本，以及事件驱动、缓存上限、旧租约和
  Bridge 生命周期回归测试。
  A repeatable RSS/CPU/thread/open-file sampler plus regression coverage for
  native events, cache bounds, legacy leases, and Bridge lifecycle events.
- Codex 与 Claude Code 保留无需 Hooks 的本地活动记录自动检测；Hooks 继续作为
  可选的精确增强，而不是首次使用的前置条件。
  Codex and Claude Code retain zero-configuration detection from local activity
  records. Hooks remain an optional precision enhancement, not a prerequisite.

### Changed / 变更

- Agent 模式不再每 4 秒递归扫描日志；现在只在模式开启时创建一个共享 FSEvents
  流，按目标文件读取新增字节，以 60 秒租约检查和 15 分钟完整校准兜底。
  Agent mode no longer recursively scans logs every four seconds. It now uses
  one shared FSEvents stream only while enabled, reads appended bytes by target
  file, and falls back to 60-second lease checks and 15-minute reconciliation.
- 设置页将自动检测与精确跟踪分层展示，并在修改 Codex/Claude 配置前显示目标路径、
  新增命令和备份说明。
  Settings now separates automatic and precise tracking and previews the target
  path, command, and backup behavior before changing Codex or Claude config.

## [0.4.1] - 2026-08-01

### Fixed / 修复

- 重新构建并发布双架构 DMG，确保从 GitHub 下载的 App 使用当前四角十字星与
  单 `Z` 图标，不再携带上一版发布包中的旧图标。
  Rebuilt and republished both architecture-specific DMGs so GitHub downloads
  contain the current four-point sparkle and single-`Z` icon instead of the
  previous release asset.
- 保持 1024×1024 源图和完整 ICNS 分辨率不变，将图标可见边界从画布的 98.4%
  调整为 84.8%，与实测的 ChatGPT 85.0% 和 Claude 83.8% 视觉尺度一致。
  Kept the 1024×1024 source and full ICNS resolution while reducing the visible
  icon boundary from 98.4% to 84.8%, matching the measured visual footprint of
  ChatGPT at 85.0% and Claude at 83.8%.

### Changed / 变更

- APP 图标采用带克制边缘高光、柔和内光和浮雕阴影的四角十字星与单 `Z`，
  同时将十字星按几何边界强制垂直居中，并加入符合 macOS 视觉尺度的透明留白。
  The app icon now uses a four-point sparkle and single `Z` with restrained edge
  highlights, inner glow, and dimensional shading, while keeping the sparkle
  geometrically centered and adding macOS-appropriate transparent safe margins.
- README 改用 288×288 的轻量图标预览，不再加载 1024×1024 的生产源图。
  The READMEs now use a lightweight 288×288 icon preview instead of loading the
  1024×1024 production source asset.

## [0.4.0] - 2026-07-31

### Added / 新增

- 分别提供 Apple Silicon 与 Intel Mac 的独立可下载 App 和 DMG。
  Separate downloadable apps and DMGs for Apple silicon and Intel Macs.
- App 内设置窗口，可选管理登录项、Codex Hooks 与 Claude Hooks。
  In-app settings for the login item and optional Codex/Claude Hooks.
- 首次启动自动展示菜单栏面板；定时模式无需任何 Agent 或额外配置。
  First launch reveals the menu bar panel; timed modes need no agent or setup.
- Ad-hoc 签名、双架构 DMG 制作和无需 Apple 发布凭据的 GitHub Release 自动化。
  Ad-hoc signing, dual-architecture DMG packaging, and GitHub Release
  automation without Apple publishing credentials.

### Changed / 变更

- Hooks 安装从命令行前置步骤改为设置中的可选增强，且只修改用户明确选择、
  本机已检测到的 Agent 配置。
  Hooks are now optional settings and only modify explicitly selected,
  locally detected agent configurations.
- 五档滑轨加入悬停光晕、加大的圆形把手、加粗轨道和带触觉反馈的弹性吸附。
  The five-position slider now has a hover glow, a larger circular thumb,
  a thicker track, haptic feedback, and spring-loaded snapping.
- 修复菜单栏面板首次显示时，第一次拖拽只激活窗口而不会移动滑块的问题。
  Fixed the first drag being consumed by window activation when the menu bar
  popover is shown for the first time.
- 菜单栏与 App 内标记统一为四角十字星和单个左倾 `Z`，并将状态栏占位收为方形。
  The menu bar and in-app marks now share a four-point sparkle with one
  left-leaning `Z`, while the status item uses a compact square footprint.
- APP 图标同步换为暖陶土橙配色的四角十字星与单 `Z` 版本。
  The app icon now uses the same four-point sparkle and single `Z` in a warm
  clay-orange palette.

## [0.3.1] - 2026-07-31

### Added / 新增

- 首个面向 GitHub 发布的完整项目基线，支持 macOS 13 及以上版本。
  Initial GitHub-ready project baseline for macOS 13 and later.
- 五档防休眠滑轨：未开启、30 分钟、1 小时、2 小时和 Agent 模式。
  Five protection modes: Off, 30 minutes, 1 hour, 2 hours, and Agent.
- Codex 与 Claude 生命周期 Hooks，以及本地任务日志兜底检测。
  Codex and Claude lifecycle Hooks with local task-log fallback detection.
- 幂等的 Hooks 安装与卸载工具，可安全合并已有配置并创建备份。
  Idempotent Hook setup and removal with safe config merging and backups.
- 中文与英文独立 README，包含软件介绍、核心功能、使用方法和安全边界。
  Separate Chinese and English READMEs covering the product, core features,
  usage, and safety boundaries.
- 五角星与三个向右上角扩展的 `Z` 组成的新 APP 图标，并提供 PNG 与 ICNS 资源。
  A new app icon featuring a five-point star and three `Z` marks expanding
  toward the upper-right, supplied as PNG and ICNS assets.
- 可重复执行的 App、图标构建脚本和本地自检工具。
  Reproducible app/icon build scripts and a local self-test utility.

### Safety / 安全

- 使用带超时的 IOKit 临时电源断言，不调用 `pmset`，不修改系统休眠设置。
  Uses timeout-protected temporary IOKit assertions without calling `pmset`
  or changing system sleep preferences.
- App 关闭、倒计时结束、Agent 结束或租约失效时自动释放电源断言。
  Releases power assertions when the app closes, a timer expires, an agent
  finishes, or an activity lease becomes stale.
