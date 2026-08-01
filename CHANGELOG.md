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

- 下一版本计划扩展对更多 Agent 的识别，并探索基于大模型 API 使用活动的任务
  监测方案；具体支持范围会在实现与隐私边界验证完成后公布。
  The next release is planned to recognize more agents and explore LLM API
  activity as a task-monitoring signal; exact integrations will be announced
  after implementation and privacy-boundary validation.

### Changed / 变更

- 放大 APP 图标的十字星与 `Z` 核心标记，并加入克制的边缘高光、柔和内光和
  浮雕阴影，同时将十字星按几何边界强制垂直居中，改善安装后的视觉重量与
  小尺寸识别。
  Enlarged the app icon's sparkle-and-`Z` mark and added restrained edge
  highlights, inner glow, and dimensional shading, while geometrically centering
  the sparkle vertically for stronger installed-app presence and small-size
  recognition.
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
