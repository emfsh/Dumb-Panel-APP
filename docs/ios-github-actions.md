# iOS GitHub Actions 打包说明

这份 Flutter App 现在可以通过 GitHub Actions 在 `macOS` runner 上做 iOS 构建。因为当前开发机是 Windows，所以 iOS 编译必须交给 GitHub 的 macOS 环境执行。

## 先说结论

- 如果你只是想确认 iOS 代码能不能编译通过，运行 `unsigned` 模式就够了。
- 如果你想拿到可安装的 `.ipa`，运行 `signed` 模式，并提前准备好 Apple 证书和描述文件。
- 当前目录本身不是 Git 仓库；要使用 GitHub Actions，先把这份代码推到你自己的 GitHub 仓库。

## 已添加的工作流

- 工作流文件：`/.github/workflows/ios-build.yml`
- 触发方式：`Actions -> iOS Build -> Run workflow`

## 模式说明

### 1. unsigned

用途：
- 只做 iOS 编译验证
- 不导出可安装 IPA

产物：
- `ios-unsigned-runner-app`
- 里面是 `Runner.app.zip`

适合场景：
- 你现在没有 Apple 证书
- 先确认 Flutter + iOS 工程能否在 macOS runner 正常通过

### 2. signed

用途：
- 导出可安装 `.ipa`

产物：
- `ios-signed-ipa`
- 里面会包含 `.ipa`，以及归档产物 `.xcarchive`

适合场景：
- 你已经准备好了 Apple 证书和 provisioning profile
- 想做自签安装或开发分发

## signed 模式要准备的 GitHub Secrets

进入仓库：

`Settings -> Secrets and variables -> Actions`

新增下面四个 Secret：

- `IOS_CERTIFICATE_P12_BASE64`
  - 你的 `.p12` 证书文件做 base64 之后的内容
- `IOS_CERTIFICATE_PASSWORD`
  - 导出 `.p12` 时设置的密码
- `IOS_PROVISIONING_PROFILE_BASE64`
  - 你的 `.mobileprovision` 文件做 base64 之后的内容
- `IOS_TEAM_ID`
  - Apple Developer Team ID

## 本项目当前 iOS 关键参数

- Bundle ID：`com.daidai.daidaiApp`
- iOS Deployment Target：`13.0`
- App 版本：`1.0.1+2`

准备证书和描述文件时，必须和当前 Bundle ID 对得上。

## 推荐操作顺序

### 路线 A：先验证能不能编译

1. 把代码推到 GitHub 仓库。
2. 打开 `Actions`。
3. 选择 `iOS Build`。
4. 点击 `Run workflow`。
5. `package_mode` 选择 `unsigned`。
6. 等待完成后，下载 `ios-unsigned-runner-app` 工件。

### 路线 B：直接导出可安装 IPA

1. 把代码推到 GitHub 仓库。
2. 在仓库里配置好 4 个 iOS Secrets。
3. 打开 `Actions`。
4. 选择 `iOS Build`。
5. 点击 `Run workflow`。
6. `package_mode` 选择 `signed`。
7. `export_method` 建议先选 `development`。
8. 等待完成后，下载 `ios-signed-ipa` 工件。

## base64 生成方式

如果你是在 macOS 上准备证书文件，可以这样生成：

```bash
base64 -i ios_certificate.p12 | pbcopy
base64 -i profile.mobileprovision | pbcopy
```

如果你是在 Windows PowerShell 上准备：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("ios_certificate.p12"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("profile.mobileprovision"))
```

## 注意事项

- 当前仓库里还没有 `ios/Podfile`，工作流会在首次运行时自动执行 `flutter create --platforms=ios .` 来补齐。
- `unsigned` 模式只说明“能编译”，不代表“能安装到 iPhone”。
- `signed` 模式依赖证书、描述文件和 Team ID 都匹配当前 Bundle ID。
- 如果后面你改了 iOS Bundle ID，证书和描述文件也要跟着重新匹配。
