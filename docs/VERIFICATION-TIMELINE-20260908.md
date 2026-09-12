# 鸿蒙时间轴测试结果

1.1.0 已构建成功。API 23 模拟器完成了原生界面与播放器测试，18 组原生逻辑检查和 24 项多时区模型检查通过。

验证包括全天索引、事件颜色区间、日期选择、断线恢复和真实录像定位。最终两处小数边界调整只重新构建，未再次安装最终二进制；不把此前运行结果当作最终包的全部验收。

默认 HAP 未签名，真机还需配置自己的签名。API 20 真机和五路物理摄像头性能尚未验证。

<details>
<summary>展开详细说明与原始记录</summary>

# Harmony 1.1.0 全天时间轴验证

本轮移除全局回放顶部横轴；通道详情改为全天垂直时间轴与上方原位原生播放，移除详情录像列表及下载入口。既有官方悬浮页签未改。历史页签证据见 [悬浮页签验证](VERIFICATION-DOCK-20260908.md)。

## 构建与交付

| 项目 | 结果 |
| --- | --- |
| 版本 / 包名 | 1.1.0，versionCode 2；com.neardi.recorder |
| 最终产物 | dist/smart-recorder-1.1.0-debug-unsigned.hap |
| 文件长度 | 807336 字节 |
| SHA256 | b09bce504479440fd461d32bf8a6ae924ca93d7bfa4fa25d005c2429f24b80aa |
| 最后构建 | Hvigor BUILD SUCCESSFUL，7.130秒；无编译错误，保留既有19条 ArkTS 警告及未配置签名提示 |
| 包完整性 | ZIP CRC 全部通过；打包 manifest 版本、包名和 phone/tablet 声明一致 |
| 最低 / 目标 / 编译 SDK | 60000020 / 60000020 / 26.0.0.105 |
| 原生运行环境 | 专用 RecorderHarmony，HarmonyOS 6.1.0.115(SP11)，API23，x86_64 |

本次原生验收包已包含程序 seek 自动起播修复及有界定位恢复，生产包也已覆盖安装并连接真实录像机。原生验收后只再修改两处整秒进度与小数日界的比较/上报，最终包纳入并构建通过，未再次安装该最终二进制；不能把整数边界实测写成小数边界已实测。最终包是模拟器未签名调试 HAP，真机安装仍需按 [BUILD.md](BUILD.md) 配置官方签名。

## 逻辑与接口

- 原生 ArkTS 隔离测试入口执行 **18/18** 组通过，含原有10组接口/媒体安全检查、新增8组时间轴检查。真实五路 `GET /api/timeline` 均成功：AHD1 为176条录像、160个合并事件区间，AHD2～5为空；未调用真实配置 PUT。证据 `native-checks.json`。
- 纯模型另用 DevEco TypeScript 在 Asia/Shanghai、America/New_York、Europe/Berlin 运行8组检查，**24/24** 通过。覆盖自然日与 DST、严格日期、跨午夜裁剪、24点排他、连续/重叠/1秒空白、清理状态、1440条完整索引、错误范围/通道/重复索引及四类事件。这部分是 Node 测试，不能替代原生媒体验收。证据 `logic-node.json`。
- 隔离 Mock HTTP 检查 **5/5** 通过：一天1154条录像及96个事件区间；测试 MP4 Range 206精确字节；旧服务404；超限422；离线503及恢复。UI 没有使用最近200条兜底。404/422本轮只完成接口与解析路径检查，未单独截取客户端错误页面。证据 `mock-http-checks.json`。
- 本仓库协议副本与 Ubuntu `docs/CLIENT_API.md` 的 SHA256 完全一致：`028c89528eb52ea603771bea65aefc209406d80d4314c4ac7f80e40ae41422aa`。

## 原生界面和播放器

| 用例 | 实际结果 / 证据文件 |
| --- | --- |
| 真实全天回放 | 上下滑动选择真实16:55:13；上方 Video 解码实际摄像头画面，录像轨与事件标记可见。`real-playback-selected.png`。此图为起播修复前，证明定位/解码，不单独作为自动播放证据。 |
| 全局与详情结构 | 全局仍有片段下载，旧顶部时间轴不存在；通道回放只有日期、缩放、图例、垂直轨，无片段列表或下载。`global-history-result.json`、`real-global-recordings.png`、`mock-four-lanes-overview.png`。 |
| 四色 / 深色 | 停留红、人蓝、车紫、动物绿均显示，文字图例辅助区分；浅深色图实际查看通过。`mock-four-lanes-overview.png`、`mock-timeline-dark.png`。 |
| 精细与日期 | 概览切精细保留时刻；原生日期选择器从9月8日改到7日，游标归当日00:00。`mock-fine-selected.json`、`mock-date-picker.png`、`mock-date-yesterday.png`。 |
| 自动起播与时钟同步 | 修复后仅拖动时间轴，未点播放，父游标21:40:15→21:40:19，原生进度00:15→00:19。`postfix-clock-a.json`、`postfix-clock-b.json`。 |
| 用户暂停 | 手点原生暂停后隔9秒，游标均21:41:41，没有错误提示或强制续播。`mock-paused-a.json`、`mock-paused-b.json`。 |
| 同一URL出错后重选 | fixture-1301断网报5411004；恢复并在同一分钟重选，逻辑URL相同、原生重载参数2→5，21:41:15→21:41:19持续播放。`mock-offline.json`、`mock-same-url-recovered-a.json`、`mock-same-url-recovered-b.json`。 |
| 无触摸自动恢复 | 离线选择片段报错，恢复Mock后不操作客户端，退避重载1→2并自动继续，21:41:22→21:41:27。`automatic-retry-error.json`、`automatic-retry-recovered-a.json`、`automatic-retry-recovered-b.json`。 |
| 跨午夜原生进度条 | 片段起点前日23:59:30，日内播放00:00:14对应文件00:44；点原生进度条最左端后被钳回文件00:31、日内00:00:01并继续。`mock-midnight-start.json`、`mock-midnight-native-clamped.png`。 |
| 续播与空白 | 实际观察连续fixture-1280→1281→1282；可用片段保持播放。选择空白或不可用分钟明确显示“该时段暂无可用录像”，不跳到其他有录像时刻。`mock-wide-stable.json`、`mock-date-picker.json`、`automatic-retry-offline.json`。 |
| 横宽 / 竖窄 | 隔离入口通过原生方向及应用密度切换，布局实际变为左视频右时间轴，再回竖向；保留已选日期、精细尺度，媒体继续。`mock-wide-stable.png`、`mock-date-picker.json`。这是窗口/逻辑宽度仿真，非真实平板。 |
| 生产入口 | 1.1.0生产包覆盖安装，真实地址192.168.10.172:8080、浅色偏好正确；最终首页1/5在线并显示AHD1实际画面。`production-110-preferences.json`、`production-110-live-stable.png`。 |

初轮原生验证发现 `VideoController.setCurrentTime` 不触发操作进度条的 `onSeeked`，原先等待该事件导致定位后停帧。已按实际行为修改：程序定位后按播放意图 start，借助 onUpdate 确认进度；确认等待8秒有界，暂停/后台不判失败，断线保留目标并重试。旧停帧证据保留，修复后的连续时钟证据单独列出。

## 日志、限制与清理

本轮抓取本应用 PID 的错误日志，没有清空系统日志。保留 `final-test-errors.log` 和 `production-errors.log`：包括 NETSTACK 读取 TCP 信息失败，以及生产预览过程中的 PixelMap ashmem-name 错误；同一时间实际画面与界面正常。所抓取窗口未发现 ArkTS 未捕获异常或业务崩溃，不能据此承诺长期稳定性。Mock媒体离线的5411004是故障注入预期结果。

真实板初次回放验收时AHD1关闭，收尾首页已恢复有信号；本代理全程只读真实接口，未写配置、未恢复通道开关。Mock配置写入记录也为0。测试媒体为明确临时目录生成的320×180/H264/15fps纯色60秒片段，已取回 `.local` 并删除板端该临时文件，不使用或改动真实录像文件。

API20真机、真实平板、长期网络抖动、万条索引持续运行与实际多通道吞吐仍需独立验收；不能将本次API23模拟器结果替代它们。原生播放器进度回调为秒级，本轮跨日原生实测使用整数30秒边界；源码对小数边界做整秒比较和上报钳制，未做帧级日界保证。本轮没有重跑所有全屏/下载流程、24:00末端原生拖动和DST系统时区媒体播放；相应纯模型或历史验收应分别引用。

专用模拟器两次测试使用的PID16316、29628均已停止，未停止用户其他设备或IDE。最终 `hdc list targets`、`hdc fport ls` 均为空；Mock进程已结束，18081无监听，Mock状态恢复normal/online。生产偏好留在实际默认地址、浅色实时页。

全部本轮证据位于 `dist/verification-timeline-20260908/`，由忽略规则排除提交；代表图和原始JSON保留供复核。最终产物摘要见 `artifact-final.json`。

</details>
