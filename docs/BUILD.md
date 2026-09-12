# 鸿蒙安装与构建

用 DevEco Studio 打开仓库文件夹，等待同步，选择模拟器或自己的设备后点击运行。

也可以在仓库根目录打开 PowerShell：

```powershell
.\build-hap.ps1
```

HAP 和日志输出到 `dist/`。默认包未签名，真机需要在 DevEco Studio 使用自己的开发者账号完成设备注册和自动签名。

最低兼容鸿蒙 6.0 / API 20，当前编译使用 API 26，已有运行测试使用 API 23 模拟器。未完成 API 20 真机验证。

DevEco 不在默认位置时，用 `-DevEcoPath` 指定安装目录。完整工具路径、模拟器命令和签名说明可展开查看。

<details>
<summary>展开详细说明与原始记录</summary>

# 构建与安装

工程使用 ArkTS、ArkUI 和 Stage 模型。最低兼容版本和目标行为版本均为 **HarmonyOS 6.0.0 / API 20**，已通过本机编译器的兼容性检查，未出现要求 API 21 及以上的接口告警。实际运行验证使用 API 23 模拟器，尚未在 API 20 真机上验收；编译 SDK 使用 DevEco Studio 的内置版本。

## 本机已验证工具链

| 工具 | 版本 / 位置 |
| --- | --- |
| DevEco Studio | `C:\Program Files\Huawei\DevEco Studio` |
| HarmonyOS SDK | 内置 API 26，`sdk\default`，版本 `26.0.0.105` |
| Hvigor / ohos-plugin | `6.26.4`，`tools\hvigor\bin\hvigorw.js` |
| Node.js | `24.14.1`，`tools\node\node.exe` |
| ohpm | `26.0.0.630`，`tools\ohpm\bin\ohpm.bat` |
| Java | JBR `25.0.2`，`jbr\bin\java.exe` |
| hdc | `sdk\default\openharmony\toolchains\hdc.exe` |
| 验证镜像 | HarmonyOS `6.1.0.115(SP11)`，API 23，x86_64 |

`build-profile.json5` 不写死 `compileSdkVersion`：当前 DevEco Studio 按官方推荐使用内置 SDK。`compatibleSdkVersion` 与 `targetSdkVersion` 保持 `6.0.0(20)`，不因编译 SDK 升级自动抬高最低版本。

## 一键构建

在本目录打开 PowerShell：

```powershell
.\build-hap.ps1

# DevEco Studio 安装在其他位置时
.\build-hap.ps1 -DevEcoPath 'D:\Tools\DevEco Studio'
```

脚本设置仅对本次构建生效的 Node、Java、SDK 路径，安装工程依赖并运行 Hvigor。当前客户端不依赖第三方运行库。机器路径写入忽略提交的 `local.properties`；日志、HAP 和 SHA-256 写入 `dist/`。构建失败会保留日志并返回失败，不能把 HAP 文件复制成功当作编译成功。

## 模拟器安装

本机 API 23 模拟器已实测允许安装未签名调试 HAP。先在 DevEco Studio 启动模拟器，再查看 hdc 设备列表；多个设备连接时必须指定目标，不向所有设备批量安装。

```powershell
$Hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $Hdc list targets

# 将地址换成上一步列出的目标；以下地址用于本工程独立测试模拟器。
$RecorderTarget = '127.0.0.1:12345'
& $Hdc -t $RecorderTarget install '.\dist\smart-recorder-1.1.0-debug-unsigned.hap'
if ($LASTEXITCODE -ne 0) { throw 'HAP 安装失败' }
& $Hdc -t $RecorderTarget shell aa start -a EntryAbility -b com.neardi.recorder
```

覆盖安装后需等待系统完成应用更新处理，再启动应用。若 hdc 显示安装成功但启动时仍处在旧应用退出动画，稍后重新启动即可。应用默认通过 `http://192.168.10.172:8080` 连接录像机。

## 真机签名

未签名 HAP 不能作为通用真机安装包。真机调试需在 DevEco Studio 打开本目录，连接设备，在 `File → Project Structure → Signing Configs` 使用 HarmonyOS 自动签名；按 IDE 提示登录华为开发者账号并注册调试设备。完成后通过 IDE 运行，或再次运行构建脚本导出签名 HAP。发布到应用市场需要对应的发布证书和 Profile。

本工程没有借用用户已有证书，也没有在仓库中放置私钥。`.p12`、`.p7b`、`.csr`、`.cer` 等签名材料与构建缓存已列入 `.gitignore`。IDE 自动签名后会更新本地 `build-profile.json5`，提交前应移除其中个人 `signingConfigs`，保留仓库原有空数组；签名密码与个人证书路径不要提交。

## 可复现的原生 UI 检查

`tools/UiHarness.ps1` 使用 SDK 自带的 hdc / uitest，按实际界面树中的控件 ID 或文字定位，保存截图和界面树。不依赖 WebView 或 Android 自动化框架。

```powershell
. .\tools\UiHarness.ps1 -Target '127.0.0.1:12345'
Get-RecorderVisibleText
Save-RecorderScreenshot -Name 'phone-live'
```

参考：[HarmonyOS 6.0.0 版本说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-600)、[华为自动签名指南](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-signing-auto)、[模拟器命令行](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)。

</details>
