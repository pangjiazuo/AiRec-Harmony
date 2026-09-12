# 底部悬浮导航测试

这份记录检查鸿蒙官方圆角悬浮导航的浅深色、内容滚动和宽窄窗口切换效果。

API 23 使用 HdsTabs 官方材质；API 20～22 有原生 Tabs 兼容分支。模拟器表现不能替代最低版本真机验收。

具体截图、当时发现的问题及修复过程保留在下方。

<details>
<summary>展开详细说明与原始记录</summary>

# 官方悬浮页签验证（2026-09-08）

本次只修改鸿蒙客户端。Ubuntu 服务、Android 客户端和板端通道配置未变动。设计与版本依据见 [DESIGN.md](DESIGN.md#底部悬浮页签与系统兼容)。

## 实现

- API 23 起接入 UI Design Kit 的 HdsTabs.barFloatingStyle 和 hdsMaterial，使用官方 ADAPTIVE 材质及温控策略，圆角与材质由组件绘制。
- API 20～22 使用原生 Tabs 的 barModifier、barOverlap、barBackgroundBlurStyle；不自行绘制面板或计算模糊。
- 新材质模块通过本地 lazy import 隔离；最低兼容和目标行为版本保持 API 20。
- API 23 所有窗口固定使用同一个官方底部浮栏，由 HDS 按断点布局；API 20～22 使用同一个 Tabs 随宽度切换底栏/侧栏。历史页不因跨越 840vp 而重新创建。滚动末端增加留白，让最后一项可移至浮栏上方。
- 主题 Radio 与整行点击统一排入下一轮事件处理，跳过当前主题，防止渲染期间重复保存与状态更新。

## 构建

Windows DevEco Studio，内置 SDK 26.0.0.105。执行 `./build-hap.ps1 -SkipInstall`，退出码 0，Hvigor 6.771 秒，33 个任务；19 条既有异常处理提示，无新增 API 兼容警告。

产物 `dist/smart-recorder-1.0.0-debug-unsigned.hap`，666,238 字节，SHA256：

    24e7a1f8ca4a850a0e03eddf1f52dfb1e5d4a7085750dc1d74fcd25c733fb59e

ZIP CRC 校验通过；包内 minAPIVersion 与 targetAPIVersion 均为 60000020，bundleName 为 com.neardi.recorder。证据：`dist/verification-dock-20260908/hap-audit.json`。

## 运行记录

仅使用专用 RecorderHarmony 模拟器（HarmonyOS 6.1.0.115 SP11 / API 23），未操作用户其他模拟器或手机。连接真实开发板只读获取状态和历史，未提交板端配置。

首轮确认了官方 HDS 节点、圆角悬浮布局、四个页签与详情返回、浅深色切换、背景内容透过浮栏及实时/设置末项可达。首次回放返回立即抓树时处于导航动画，稳定后重测通过，保留两次记录。

首轮日志发现主题更新时机问题与 HDS 构造选项提示，随后修正主题回调，并显式传入 HdsTabsController 与 barPosition。第二轮浅色→深色→浅色复测未再出现这三类错误；记录为 `final-app-log-results.json`，浅深色截图为 `final-dock-*.png`。

模拟器的 `RecorderUI` 能力日志明确为 `API=23, supportedMaterials=[], adaptive=true`，HDS 另有材质配置不可用的内部日志。因此目前确认的是官方浮栏的圆角与半透明降级表现，未确认截图参考所示的完整沉浸毛玻璃。保留官方自适应策略，没有叠加自制滤镜掩盖模拟器能力限制。

传统分支测试发现 calc 字符串未产生预期左右留白，已改为实际窗口 vp 宽度减 32；复测左右各 56px（16vp），横向宽窗口侧栏与返回恢复正常。

首次只改变模拟器密度，没有改变 Navigation 像素外框，不能证明进入侧栏分支；此失败覆盖记录保留于 `density-only-results.json`。随后采用官方窗口 LANDSCAPE/PORTRAIT 接口同时改变实际像素外框。初版 HDS 底栏/侧栏切换虽保留了“人”筛选与节点标识，返回实图却出现底板右移，`native-real-narrow-return.png` 是失败证据，不能仅凭节点指标判定视觉通过。

最终实现取消 HDS 栏形态切换及 barWidth/barHeight 覆盖，各尺寸都使用官方底部浮栏。最后对 `fixed-native-wide.png` 与 `fixed-native-narrow-return.png` 实际看图复核：宽屏浮栏居中并包住全部四项，返回窄屏后左右各 56px 留白，底板不偏移、不出屏；“人”筛选及 HdsTabs 节点保持不变。测试包使用真实窗口方向变化和 density 1 / 3.5 组合检查布局，未把这种宽视口模拟称为实体平板验收。证据为 `fixed-native-visual-results.json`。

最终交付包再次安装启动，通过浅深色事件页面实图检查，截图为 `delivered-events-light.png`、`delivered-events-dark.png`。交付摘要、日志与清理记录分别为 `delivered-results.json`、`delivered-app-errors.txt`、`delivered-cleanup.json`；专用模拟器在恢复生产包的默认连接、浅色实时页后停止。

## 验证边界

系统按设备能力及设置选择实际材质等级。仅看到半透明截图不能证明截图所示的强毛玻璃效果已经完整生效；系统材质能力查询也不能当作当前帧实际档位。

API 20～22 尚无对应系统真机/镜像可验收。隔离测试包可以在 API 23 强制传统分支检查布局，这不等同于 API 20 启动测试。真机玻璃效果、低端机温控降级及各类字体放大需分别验收。

产物仍为未签名调试 HAP；真机需在 DevEco Studio 使用用户自己的开发者账号与官方自动签名。安装与签名方法见 [BUILD.md](BUILD.md)。

</details>
