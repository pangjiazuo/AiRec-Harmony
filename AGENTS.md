# HarmonyOS 客户端开发约定

- 本目录是可单独提交、克隆和构建的 ArkTS / ArkUI 客户端仓库，使用 Stage 模型，构建不能依赖父目录、Ubuntu 或 Android 源码。
- 兼容鸿蒙 6.0 起：compatibleSdkVersion 与 targetSdkVersion 保持 6.0.0(20)，当前 DevEco 默认内置 API 26 编译。不要仅因 SDK 较新或新增材质就抬高最低版本；基础分支使用 API 20 及之前能力，更高版本可选能力必须按实际系统 API 守卫并提供旧版本原生实现。
- 使用鸿蒙原生 ArkUI 控件，依据官方设计指南。页面保持五路视频墙、通道详情、原生回放、事件筛选、设备信息、分类设置；支持手机/平板、横竖屏与浅色/深色/跟随系统，默认浅色。映射及来源见 docs/DESIGN.md。
- API 23 起所有窗口尺寸均使用同一 NativeFloatingTabs / HdsTabs 实例的官方底部悬浮圆角页签，采用 UI Design Kit HdsTabs.barFloatingStyle；不设置 barWidth、barHeight，由官方组件按断点适配几何。systemMaterialEffect 中 hdsMaterial.MaterialType.ADAPTIVE 与 MaterialLevel.ADAPTIVE，保留 thermoCtrl:true，由系统决定材质与温控表现。宽屏只调整内容网格，不切换为侧栏，避免原生悬浮背景与页签几何错位；保持子页实例、历史筛选和下载任务。官方接口见 [HdsTabs](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs)、[hdsMaterial](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsmaterial)。
- API 20～22 保留同一个原生 Tabs：宽度小于 840vp 时，使用 TabsOptions.barModifier/CommonModifier 圆角与 Tabs.barOverlap、barBackgroundBlurStyle(COMPONENT_REGULAR)，以实测窗口宽度减 32vp 设置页签宽度；达到 840vp 切换原生侧栏。不得宣称旧系统获得 API 23 沉浸光感；窗口切换时显式恢复不再需要的修饰属性，不假设将 barModifier 改为 undefined 会清除旧值。
- API 23 新组件和 Kit 导入隔离在 NativeFloatingTabs.ets；Index.ets 通过本地模块 import lazy 与 sdkApiVersion >= 23 守卫延迟引用，模块内部也保留守卫。遵循 [官方 lazy import 规则](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V13/arkts-lazy-import-V13)，不直接 lazy 导入 Kit，也不添加绕过隔离的普通导入。
- 玻璃效果仅使用官方 UI Design Kit/ArkUI 材质与模糊，不自绘面板、不加自定义着色器、不用截图或视频位图模糊模拟。List 用 contentEndOffset、Scroll 用内容底部 padding 补偿悬浮页签，允许内容经过材质下方且保证末项可滚上来点击。API 23 起所有尺寸的主页面均保留 96vp Dock 补偿；API 20～22 窄屏保留 96vp，宽屏侧栏模式设为 0，另叠加页面常规留白。
- 材质改动分别核对系统版本、浅深色、滚动穿过效果、末项可达与窄宽窗口切换；只写实际执行结果。构建成功不等于视觉验收或 API 20～22 真机测试通过。
- 使用 Windows PowerShell / DevEco Studio，构建用 build-hap.ps1，步骤见 docs/BUILD.md。检查退出码并保存日志，不能把复制 HAP 成功当作编译或运行通过。
- 默认板端地址 http://192.168.10.172:8080，可在客户端修改。通过 HTTP API 调用板端业务；主题和地址只写本机偏好，不提交板端配置。
- 数据模型、HTTP/配置合并、媒体连接与 UI 分目录。保持简单易读，添加适量中文注释；无信号、单路断线、模型故障不能阻塞其他通道。
- MJPEG 每路独立超时重试，切页/后台释放连接与 PixelMap，限制等待帧数量。视频保持宽高比，布局切换不创建第二个播放器。
- 保存前获取完整最新配置，仅合并用户实际编辑字段。草稿按设备/通道隔离；批量应用列出目标，统一保存后生效，保留目标名称、通道开关、source/crop 和未知字段。
- 协议副本在 docs/CLIENT_API.md，同步见 docs/API_SYNC.md。全局历史列表仍最多 200 条；通道全天回放必须调用 /api/timeline，完整查询所选本地零点到翌日零点，支持 DST 23/25 小时。404 提示升级，422/503 明确错误，不从 200 条补造全天覆盖。
- 下载使用原生文件选择器；保留流式接收、大小限制、取消与失败清理，不把整个录像载入 ArkTS 内存。
- 模拟器与最低系统兼容性分别报告。本机验证镜像为 HarmonyOS 6.1 / API 23，不能称为 API 20 真机测试。截图和结果须来自实际执行，不预写通过结论。
- hdc 必须指定目标，只操作任务选定模拟器，不停止用户其他模拟器、不向全部设备安装/卸载。配置 PUT 验证使用隔离 Mock；普通真实板端只读验收不改设置。
- 默认输出未签名调试 HAP，不称为通用真机已签名安装包。真机需用户在 DevEco 使用自己的账号、设备注册和官方自动签名。不得代用其他项目证书或读取/输出私钥密码。
- local.properties、.local/、缓存、构建产物、证书/私钥不提交。IDE 写入 build-profile.json5 的个人签名条目提交前清除，保留可分享的空 signingConfigs。
- 客户端在 Windows 构建，不将 HAP、SDK、Hvigor 缓存部署至 ARM 开发板；普通客户端修改不重启板端服务。

- 通道详情回放只保留全天垂直时间轴，播放器在上方原位替换直播；详情和其全屏没有下载入口，全局回放保留下载。概览/精细缩放保持时刻，停滑后再定位；只有相接/重叠的可用片段自动续播，间隙/清理/日末停止，原生进度条也不得越过所选日期裁剪范围。
- 全天索引用 TimelineState/ObjectLink 共享，Canvas 只绘制可见色带；不能每秒深拷贝全天数据或一次为万条记录创建控件。新选时必须递增请求 serial，同 URL 出错后重选必须更新实际 src 重新准备。
