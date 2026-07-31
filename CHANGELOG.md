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

### Added / 新增

- 可独立下载的 Universal 2 App 构建，覆盖 Apple Silicon 与 Intel Mac。
  Universal 2 app builds for both Apple silicon and Intel Macs.
- App 内设置窗口，可选管理登录项、Codex Hooks 与 Claude Hooks。
  In-app settings for the login item and optional Codex/Claude Hooks.
- 首次启动自动展示菜单栏面板；定时模式无需任何 Agent 或额外配置。
  First launch reveals the menu bar panel; timed modes need no agent or setup.
- Developer ID 签名、Apple 公证、DMG 制作和 GitHub Release 自动化。
  Developer ID signing, notarization, DMG packaging, and release automation.

### Changed / 变更

- Hooks 安装从命令行前置步骤改为设置中的可选增强，且只修改用户明确选择、
  本机已检测到的 Agent 配置。
  Hooks are now optional settings and only modify explicitly selected,
  locally detected agent configurations.

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
