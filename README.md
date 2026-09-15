# AiRec 鸿蒙客户端

用鸿蒙手机或平板查看五路摄像头、回放录像、筛选事件和修改录像机设置。采用鸿蒙原生界面，支持 **HarmonyOS 6.0 及以上**及浅色、深色模式。

## 安装与连接

1. 用 DevEco Studio 打开本工程，等待同步完成。
2. 选择模拟器运行；真机需使用自己的开发者账号完成设备注册和自动签名，再安装运行。
3. 与 AiRec 录像机连接同一局域网，在设置中填写 `http://录像机IP:8080`，例如 `http://192.168.10.209:8080`。

需要配合 [安卓录像主机](https://github.com/pangjiazuo/AiRec-Host-Android) 或 [Ubuntu 录像机](https://github.com/pangjiazuo/AiRec-Rec) 使用。

[Releases](https://github.com/pangjiazuo/AiRec-Harmony/releases) 中的 HAP 是未签名调试包，不能直接安装到普通真机。详细步骤见[签名与安装](docs/BUILD.md)。

## 界面

| 实时画面 | 录像回放 | 设置 |
| --- | --- | --- |
| <img src="docs/screenshots/live.png" width="240"> | <img src="docs/screenshots/recordings.png" width="240"> | <img src="docs/screenshots/settings.png" width="240"> |

## 自行构建

在 PowerShell 运行 `./build-hap.ps1`，HAP 输出到 `dist/`。首次构建需要联网。目前已在 API 23 模拟器验证，最低支持版本 API 20 尚未完成真机验证。

[更多说明](docs/README.md) · [马赛克设置](docs/PRIVACY.md)
