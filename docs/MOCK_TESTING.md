# 不连接真实录像机进行测试

这个工具为开发者提供假的配置和接口数据，用来检查设置保存、日志下载和断网重连，不会更改真实开发板。

1. 在仓库根目录启动 `tools/mock_recorder.py`。
2. 给选定模拟器配置端口转发，并把应用地址改成测试地址。
3. 完成后停止测试进程，把应用地址改回自己的录像机。

它不能代替摄像头、NPU 或真实录像性能测试。下面提供完整命令。

<details>
<summary>展开详细说明与原始记录</summary>

# 隔离配置联调

`tools/mock_recorder.py` 使用 Python 标准库，只监听 Windows 的 `127.0.0.1`，不会连接真实开发板。它提供独立的五路配置、存储选项和可下载的测试 ZIP；PUT 只修改测试进程内存，并写入本地报告。它不模拟实际采集、识别或 MP4 编解码能力。

在 `AiRec-Harmony/` 打开 PowerShell，启动服务：

```powershell
python .\tools\mock_recorder.py --port 18081 --report .local\mock-state.json
```

使用 SDK 的 hdc 给**明确选定的测试模拟器**建立设备到本机的端口转发，再把客户端地址改为 `http://127.0.0.1:18081`。不要把测试地址写入应用默认配置，也不要将写入用例指向实际录像机。

```powershell
$Hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$RecorderTarget = '127.0.0.1:12345' # 替换为实际测试目标
& $Hdc -t $RecorderTarget rport tcp:18081 tcp:18081
if ($LASTEXITCODE -ne 0) { throw '测试端口转发失败' }
```

通过客户端修改通道参数、应用到其他通道、保存存储设置。查看 `.local/mock-state.json` 中的 `original`、`config` 与 `writes`，核对修改值以及各路名称、启用状态、source、crop、未知字段是否保留。默认只有 AHD1 启用；Mock 所有通道均无视频信号。

以下操作只改变 Mock 的可用状态，用于验证客户端自动重连：

```powershell
Invoke-RestMethod -Method Put -Uri 'http://127.0.0.1:18081/__test__/offline' `
    -ContentType 'application/json' -Body '{"offline":true}'
# 确认客户端显示连接中断后，恢复服务响应。
Invoke-RestMethod -Method Put -Uri 'http://127.0.0.1:18081/__test__/offline' `
    -ContentType 'application/json' -Body '{"offline":false}'
```

`GET /__test__/state` 返回配置与写入历史，`GET /api/logs/download` 返回包含 `fixture.log` 的测试 ZIP。这个工具用于客户端交互测试，不代替后端的参数校验测试，也不能证明五路硬件采集或外置 SD 卡性能。

结束后恢复客户端实际录像机地址，停止本次 Mock 进程并移除本次端口转发。只清理本次测试实例，不停止全局 hdc 或其他模拟器。

## 全天时间轴与原位播放器

Mock 也提供 `/api/timeline`，不依赖真实板端。AHD1 每日返回超过200条的完整分钟索引，包含跨零点片段、相接片段、2分钟空白、已清理片段和四类事件；其他路为空。

给 `--video .local/timeline-minute.mp4` 指定自行生成的60秒测试MP4，可测试原生播放与单段Range；服务只读取明确指定的本地文件，不下载媒体、不连接上游。没有该参数时媒体请求明确失败。所有索引片段复用这份测试视频，不能据此判断真实摄像头画质或五路吞吐。

`PUT /__test__/timeline_mode` 的 JSON `mode` 可选 `normal`、`legacy`（404）、`oversize`（422）或 `delay`（10秒响应延迟），用于升级提示、超限和取消旧请求测试。它只修改此 Mock。原有 `offline` 模式同时影响索引和测试媒体。

运行 `tools/prepare-timeline-harness.ps1` 将当前源码复制到本工程 `.local/signing-smoke`，包名改成 `com.neardi.recorder.tests`，替换为独立测试入口。该脚本不会构建、启动模拟器或修改生产入口。隔离包 `aa start --pb runChecks true` 执行18组原生逻辑及真实板端五路时间轴GET，将结果写入应用 files/timeline-checks.json；不会调用真实配置PUT。`--pb testWide true/false` 通过官方窗口方向和测试应用密度切换横宽/竖窄布局，不能当作真实平板或API20测试。

</details>
