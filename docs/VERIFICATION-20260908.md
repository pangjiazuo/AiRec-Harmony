# 鸿蒙早期测试记录

这里记录了鸿蒙客户端初版的构建、预览、回放、设置和日志下载检查，测试使用 API 23 模拟器。

当前时间轴版本请看 [最新测试记录](VERIFICATION-TIMELINE-20260908.md)。早期安装包、耗时和运行结果仅代表当时版本，不代表 API 20 真机已经通过测试。

<details>
<summary>展开详细说明与原始记录</summary>

# 鸿蒙客户端验证记录（2026-09-08）

## 构建结果

- 工程：`harmony/`，原生 ArkTS / ArkUI / Stage 模型，没有 WebView。
- 包名：`com.neardi.recorder`，版本 `1.0.0`（1），设备类型 `phone` / `tablet`。
- 最终构建命令：`./build-hap.ps1 -SkipInstall`。Hvigor 6.26.4 在 18.182 秒内完成 33 个任务，`BUILD SUCCESSFUL`。
- 产物：`dist/smart-recorder-1.0.0-debug-unsigned.hap`，644,062 字节。
- SHA-256：`c828eba0cb28fda5b764c0e328aafd4fc4631562ac6c717e4325c37a811a7ab2`。
- HAP 的 ZIP CRC 校验通过。打包清单的 `minAPIVersion` / `targetAPIVersion` 均为 `60000020`，`compileSdkVersion` 为 `26.0.0.105`。
- 编译仍有 19 条系统接口可能抛异常的提示；没有 API 21 及以上接口兼容告警。该检查不能代替 API 20 真机运行验证。
- 构建脚本先将明确输出目录内的旧 HAP 归档到忽略提交的 `.local/previous-haps/`，本次已实际验证重新打包，避免误交付旧签名包。

本机 API 23 模拟器允许安装该未签名 HAP，已完成安装和启动。**本包不能作为通用真机签名安装包**；连接真实鸿蒙设备后，需要使用自己的华为开发者账号在 DevEco Studio 配置 HarmonyOS 调试签名。未使用、读取或提交用户的个人签名证书、私钥。

## 环境与隔离范围

本机工具链是 DevEco Studio 内置 API 26 SDK、Node 24.14.1、JBR 25.0.2。运行镜像为 HarmonyOS 6.1.0.115(SP11)，API 23，x86_64。

本轮仅创建并使用独立模拟器 `RecorderHarmony`（1256×2760、560 dpi、2 GB 内存），没有停止或更改用户已有的 Mate 80 实例、其他 IDE、Android 设备。测试应用 `com.neardi.recorder.tests` 使用独立包名和偏好，未覆盖正式客户端。

真实录像机 `192.168.10.172:8080` 仅执行 GET、预览、回放和日志导出。所有配置 PUT 均指向 Windows 回环地址的隔离 Mock，经本次专用 hdc 端口映射访问；Mock 不连接真实开发板。

## 实际运行结果

| 范围 | 已确认结果 | 本地证据 |
| --- | --- | --- |
| 原生逻辑测试 | 最新 10/10 组通过：地址与同源媒体、最新配置合并、复制保留身份、参数范围、未知指标、异常 JSON、循环清理记录、模型/介质数据、MJPEG 分片和坏帧防护 | `final-native-results.json`、`native-test-entry.ets` |
| 最新板端协议解析 | 原生 NetworkKit GET 状态、配置、录像、事件、模型、存储目标、日志 7 项全部通过严格 JSON 解析；当时读到 5 通道、176 个录像、167 个事件、YOLOv5s ReLU | `final-native-results.json` |
| 真实实时预览 | 初期 AHD1 有信号时收到 5 帧真实 MJPEG，并在原生 Image 中显示；其余四路无信号正常显示，不阻塞页面 | `board-core-results.json`、`phone-dark-restarted.png`、`channel-one-initial.png` |
| 真实录像 | 原生 Video 解码实际 MP4；初测 04:59 片段可播放和暂停。最终包再次播放 01:31 片段，原生 Slider 定位 00:46，恢复播放后前进至 00:48；原生全屏与返回成功 | `playback-stable.json`、`playback-paused.json`、`final-video-seek.json`、`final-video-resume.json`、`final-video-fullscreen.png`、`final-video-fullscreen-return.json` |
| 事件筛选 | 长时间停留、人、车、动物四种原生 Select 筛选均可切换；车和动物为空时正确显示空状态 | `event-filter-results.json`、`events-initial.png` |
| 日志导出 | 原生日志列表、真实 ZIP 下载、系统 DocumentViewPicker 选择 Download、保存成功约 0.2 MB | `real-logs-picker.png`、`real-logs-saved.json` |
| 单路设置 | 在 Mock 把 AHD1 名称改为 GateTest、录像片段从 3 分钟改为 1 分钟，仅修改该路；产生一次 PUT | `mock-single-save.json` |
| 应用到其他通道 | 原生确认框加入待保存后保存，另外四路片段均改成 1 分钟，名称、启用开关、接线、裁剪、未知字段保留 | `mock-bulk-save.json`、`mock-copy-confirm.json` |
| 外置介质 | 在 Mock 原生 Select 选择 SD 卡并保存，目标为 `uuid:fixture-sd`；三次 PUT 后所有未编辑字段仍保留 | `mock-storage-save.json`、`mock-preservation-results.json`、`mock-invariants.json` |
| 断网恢复 | 同一 Mock 地址返回 503 后出现自动重连提示；恢复后无需点击刷新，设备指标重新显示，40℃测试值确认仍连接原 Mock | `mock-reconnect-results.json`、`mock-reconnect-offline.json`、`mock-reconnect-passed.json` |
| 外观与页面结构 | 最终主包浅色、深色正常；跟随系统选项可选，深色偏好经重启保持。最终 AHD1 明确显示“通道已关闭”，其他四路显示“暂无信号”。通道卡先进入预览/回放/事件页，右上角原生菜单进入通道设置；全局设置按类别展示 | `final-phone-light.png`、`final-phone-dark.png`、`final-disabled-channel.json`、`appearance-system-result.json`、`mock-channel-detail.json` |
| 宽屏布局 | 复制生产 UI 到测试包，只在测试 EntryAbility 使用 `setCustomDensity(1)`，验证 1256 vp 宽时原生侧栏、三列通道布局 | `wide-density-layout.json`、`wide-density-light.png` |
| 原生横屏 | 同一测试包调用 `setPreferredOrientation(LANDSCAPE)` 后成功切换到 2760×1256，UI 正常呈现，宿主没有再次崩溃 | `native-landscape-layout.json`、`native-landscape-light.png` |

表中证据位于本机 `dist/verification-20260908/`，构建与运行产物均忽略提交。原生逻辑测试源码 `entry/src/main/ets/data/LogicChecks.ets` 保留在仓库；隔离入口的源码快照也保存在本地证据目录。

## 必须保留的限制与异常记录

1. **没有 API 20 真机、真实平板和五个已接入摄像头的整机验收。** API 20 是最低兼容配置和编译检查结果；宽屏验证使用应用逻辑密度模拟，不能宣称实际平板尺寸、性能或触控体验已经验收。
2. 后续复测时，真实 AHD1 已变成 `enabled=false`、`recording.enabled=false`，其余四路无信号。日志不含客户端来源，无法确定关闭来源。本测试未恢复启用，因此最新综合原生测试的附加 MJPEG 步骤超时，原始结果保留 `status: failed`；这不改变前面的 10 组逻辑和 7 项 GET 通过事实。最终浅/深截图展示的是这一实际无信号状态。
3. 首次调用宿主 `Emulator.exe -rotation left` 时，Emulator 26.0.0.400 曾崩溃，错误码 `00802003`，日志记录 Intel Arc 130V GPU。仅重启自有实例一次后继续测试。后续通过原生窗口接口成功横屏；仍未验证持续来回旋转、MP4 旋转后保位的长期稳定性。
4. NativeDownloader 会验证下载长度、文件头、原生请求成功与保存后大小。普通 hdc 无权读取系统 DocumentViewPicker 的 Download 目录，未为此提升权限，因此没有独立提取已导出的真实日志 ZIP 做 CRC；HAP 本身的 ZIP CRC 已独立检查。
5. 未做五路同时实际视频解码的性能基准、长时间弱网浸泡、系统后台反复恢复或耗电测试。服务器报告的预览帧率不是客户端实际呈现帧率的测量。
6. 没有把尚未安装的外置介质挂载为真实板卡目录；SD 选择与配置保存链路使用隔离 Mock 验证。
7. 17:10:15 曾记录一次本应用 `THREAD_BLOCK_6S`，当前事件为 `MMITask`，进程退出使堆栈采集未完成，不能定位到具体 ArkTS 函数。同一时间窗口也记录 SceneBoard 应用冻结和系统冻结，Windows 当时可用内存约 690 MB。来源未定，不能断言由宿主导致或已经修复。串行验证和重新启动后未再复现，仍需真机稳定性验收。证据为 `appfreeze-recorder-171015.log`、`final-faultlogs.txt`；没有据此猜测修改源码。

## 测试清理

主应用本机偏好已恢复为 `http://192.168.10.172:8080` 和浅色，最后返回实时页。停止了本次独立 `RecorderHarmony` 实例（PID 29320）；确认进程退出、hdc 目标列表为空，端口任务列表也为空，测试反向映射不再存在。仅本次 Mock 服务已停止，用户原有实例和其他应用未操作。清理证据为 `cleanup-results.json`。

## 复现方法

先按 `BUILD.md` 构建并安装。使用 `tools/UiHarness.ps1` 读取实际原生组件树、按 ID 定位和截图；使用 `tools/mock_recorder.py` 启动独立回环测试服务。配置写入测试必须核实应用地址和 Mock 审计记录，不要对实际录像机重复执行这些写入用例。

原生纯逻辑测试入口调用 `runLogicChecks()`；板端只读检查使用同一生产 `RecorderApi`。测试入口不随正式 HAP 的应用页面导航发布。

</details>
