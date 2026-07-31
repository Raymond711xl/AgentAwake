# AgentAwake 发布说明

AgentAwake 的公开发行物是经过 Developer ID 签名和 Apple 公证的 Universal 2
macOS App。公开 Release 不应上传 ad-hoc 签名的本地产物。

## 发布前提

- Apple Developer Program 账号；
- `Developer ID Application` 证书；
- Apple 公证所需的 Apple ID、Team ID 与 App 专用密码；
- GitHub Actions 中已经配置下列 Secrets：
  - `DEVELOPER_ID_P12_BASE64`
  - `DEVELOPER_ID_P12_PASSWORD`
  - `DEVELOPER_ID_APPLICATION`
  - `BUILD_KEYCHAIN_PASSWORD`
  - `NOTARY_APPLE_ID`
  - `NOTARY_APP_PASSWORD`
  - `APPLE_TEAM_ID`

## 本地验证

```bash
swift run --disable-sandbox AgentAwakeSelfTest
./scripts/build-app.sh release universal
codesign --verify --deep --strict --verbose=2 dist/AgentAwake.app
file dist/AgentAwake.app/Contents/MacOS/AgentAwake
```

本地构建使用 ad-hoc 签名，只能用于开发验证，不能作为公开下载包。

## 正式打包

先把公证凭据保存为钥匙串 Profile：

```bash
xcrun notarytool store-credentials agentawake-notary
```

然后执行：

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: ..." \
NOTARY_KEYCHAIN_PROFILE="agentawake-notary" \
./scripts/package-release.sh
```

如果 Profile 保存于非默认钥匙串，同时传入
`NOTARY_KEYCHAIN=/path/to/keychain-db`。

脚本会依次完成：Universal 2 构建、嵌套 helper 签名、App 签名、DMG 制作、
Apple 公证、票据装订、Gatekeeper 验证、ZIP 制作和 SHA-256 校验。

## GitHub Release

1. 确认 `Resources/Info.plist`、README 与 Changelog 版本一致。
2. 确认 `main` 的 CI 通过。
3. 创建与版本一致的 Tag，例如 `v0.4.0`。
4. 推送 Tag 后，`.github/workflows/release.yml` 自动发布 DMG、ZIP 和校验文件。
5. 在一台干净的 Mac 上从 GitHub Release 真实下载并完成最终验收。

## 最终验收

- 用户不需要 Xcode、Swift、Codex、Claude 或 Cloud；
- ZIP 解压后可直接双击 App，DMG 可按标准方式拖入“应用程序”；
- Gatekeeper 认可开发者和公证票据；
- 主程序与两个 helper 均包含 `arm64` 和 `x86_64`；
- 不安装 Hooks 时，定时模式和本地日志兜底仍可使用；
- Hooks 只能由用户在设置中明确选择安装或移除。
