# AgentAwake 发布说明

AgentAwake 当前采用无 Apple 付费凭据的快速公开发布路线：主程序和两个 helper
使用 ad-hoc 签名，GitHub Release 分别提供 Apple Silicon 与 Intel DMG。

这条路线不需要 Apple Developer Program、Developer ID、Team ID、公证密码或
GitHub Actions Secrets。代价是用户首次打开时可能需要在“系统设置 → 隐私与安全性”
中点击一次“仍要打开”；README 必须始终保留这一步的明确说明。

## 本地验证

```bash
swift run --disable-sandbox AgentAwakeSelfTest
./scripts/build-app.sh release arm64
codesign --verify --deep --strict --verbose=2 dist/AgentAwake.app
file dist/AgentAwake.app/Contents/MacOS/AgentAwake
```

本地和公开版本都使用 ad-hoc 签名。该签名可验证 App 内容在打包后没有损坏，
但不会建立 Apple 开发者身份，也不会获得 Apple 公证票据。

## 正式打包

```bash
./scripts/package-release.sh
```

脚本会分别交叉编译 `arm64` 与 `x86_64`，验证主程序及两个 helper 的实际架构，
进行 ad-hoc 签名，制作并验证两个 DMG，最后生成一个 SHA-256 校验文件：

- `AgentAwake-x.y.z-Apple-Silicon.dmg`
- `AgentAwake-x.y.z-Intel.dmg`
- `AgentAwake-x.y.z.sha256`

## GitHub Release

1. 确认 `Resources/Info.plist`、README 与 Changelog 版本一致。
2. 确认 `main` 的 CI 通过。
3. 创建与版本一致的 Tag，例如 `v0.4.0`。
4. 推送 Tag 后，`.github/workflows/release.yml` 无需 Secrets 即可自动发布两个
   DMG 和校验文件。
5. 在一台干净的 Mac 上从 GitHub Release 真实下载并完成最终验收。

## 最终验收

- 用户不需要 Xcode、Swift、Codex、Claude 或 Cloud；
- README 已写明 Gatekeeper 首次放行步骤，且不要求终端命令；
- Apple Silicon DMG 的主程序及两个 helper 仅包含 `arm64`；
- Intel DMG 的主程序及两个 helper 仅包含 `x86_64`；
- 两个 App 均通过严格的 ad-hoc 代码签名验证，两个 DMG 均通过 `hdiutil verify`；
- 不安装 Hooks 时，定时模式和本地日志兜底仍可使用；
- Hooks 只能由用户在设置中明确选择安装或移除。
