# AgentAwake 发布说明

AgentAwake 的公开发行物是一个经过 Developer ID 签名和 Apple 公证的 Universal 2
DMG，内部包含原生 macOS App。公开 Release 不应上传 ZIP 或 ad-hoc 签名的本地产物。

## 发布前提

- Apple Developer Program 账号；
- `Developer ID Application` 证书；
- Apple 公证所需的 Apple Account、Team ID 与 App 专用密码。

### 获取 Developer ID 身份

1. 加入 [Apple Developer Program](https://developer.apple.com/programs/enroll/)；
   个人账号的持有人就是 Account Holder。
2. 在“钥匙串访问”中选择“钥匙串访问 > 证书助理 > 从证书颁发机构请求证书”，
   将 CSR 保存到磁盘。Apple 的完整步骤见
   [Create a certificate signing request](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request)。
3. 登录 Apple Developer 的 `Certificates, Identifiers & Profiles`，进入
   `Certificates`，点击 `+`，在 `Software` 下选择 `Developer ID`，然后选择
   `Developer ID Application` 并上传 CSR。不要选择 `Developer ID Installer`；
   后者只用于 `.pkg` 安装器。
4. 下载 `.cer` 并双击安装。钥匙串的“我的证书”中应出现
   `Developer ID Application: 名称 (TEAMID)`，展开后还能看到对应私钥。

Developer ID 证书的官方步骤见
[Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)。
Team ID 可在 Apple Developer 账号的 `Membership details` 中找到。

### 公证凭据

在 [account.apple.com](https://account.apple.com/) 的“登录与安全 > App 专用密码”
生成一个专用密码，然后使用 `notarytool store-credentials` 保存到本机钥匙串。
不要在 Issue、PR、聊天或仓库文件中粘贴 Apple Account 密码、App 专用密码、
私钥、`.p12` 文件或 `.p12` 密码。

### GitHub Actions 自动发布（可选）

第一次正式发布可以完全在本机完成，不要求先配置 GitHub Secrets。若要让 Tag
自动触发签名、公证和 Release，需要把证书与私钥导出为受密码保护的 `.p12`，
并由仓库管理员在 GitHub Actions 中配置：

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
Apple 公证、票据装订、Gatekeeper 验证和 SHA-256 校验。

## GitHub Release

1. 确认 `Resources/Info.plist`、README 与 Changelog 版本一致。
2. 确认 `main` 的 CI 通过。
3. 创建与版本一致的 Tag，例如 `v0.4.0`。
4. 推送 Tag 后，`.github/workflows/release.yml` 自动发布 DMG 和校验文件。
5. 在一台干净的 Mac 上从 GitHub Release 真实下载并完成最终验收。

## 最终验收

- 用户不需要 Xcode、Swift、Codex、Claude 或 Cloud；
- DMG 打开后可直接双击 App；拖入“应用程序”仅作为长期使用的推荐步骤；
- Gatekeeper 认可开发者和公证票据；
- 主程序与两个 helper 均包含 `arm64` 和 `x86_64`；
- 不安装 Hooks 时，定时模式和本地日志兜底仍可使用；
- Hooks 只能由用户在设置中明确选择安装或移除。
