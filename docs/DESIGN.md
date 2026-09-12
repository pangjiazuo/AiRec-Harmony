# 鸿蒙界面设计

应用有四个主页面：实时、回放、事件和设置。点击摄像头进入通道详情，在同一页面查看画面、滑动时间轴和调整该通道设置。

界面使用鸿蒙原生控件，支持手机、平板、横竖屏及浅深色。底部圆角悬浮导航和材质效果由官方组件提供。

API 23 及以上使用 HdsTabs；API 20～22 使用原生 Tabs 兼容实现。不同系统的材质和布局效果可能不同。官方设计依据及源码对应关系保留在下方。

<details>
<summary>展开详细说明与原始记录</summary>

# 鸿蒙原生界面设计说明

保留用户所选方案 B 的录像机操作结构：五路等权画面、通道详情中的预览与历史、事件分类和分层设置。界面使用 HarmonyOS 原生导航、列表、表单、播放器和选择器。本文记录设计依据与源码实现，不代替实际设备验收。

## 官方依据

华为 [设计与开发指南](https://developer.huawei.com/consumer/cn/app/planning/) 把导航、布局、交互和视觉作为整体设计。工程将全局页签、通道详情和设置子页分开，具体录像机业务流程来自本项目需求。

[布局基础](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/design-layout-basics-0000001795579413) 推荐随窗口宽高和方向调整排布、考虑安全区，并使用 vp/fp 与弹性布局。工程按实际窗口切换列数和主从区域，视频保持 16:9；常用留白为 16/24vp，细节按 4vp 调整。

[Navigation 架构](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/arkts-navigation-architecture) 与 [NavDestination 子页](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/arkts-navigation-navdestination) 是导航依据。原生标题栏承载返回和通道设置菜单，路由传递通道、媒体地址、片段时间及播放起点。

多端布局参考华为 [长视频多端开发示例](https://developer.huawei.com/consumer/cn/doc/best-practices-V14/multi-video-app-V14)。本工程宽窗口阈值为 840vp，用于内容排布；API 20～22 还据此将页签转换为侧栏，API 23 起所有窗口尺寸保留官方 HdsTabs 底部悬浮页签。详情和播放器结合宽高比处理手机横屏，具体内容尺寸是项目实现选择。

主题使用语义颜色与浅深资源，参考官方 [主题换肤说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V13/theme_skinning-V13)。本工程通过 ApplicationContext.setColorMode 与 resources/base、resources/dark 切换应用颜色模式，三态选择保存在本机。

## 底部悬浮页签与系统兼容

用户要求底部采用官方玻璃圆角 Dock。应用根据实际运行系统的 API 级别选择官方悬浮材质或 ArkUI 原生模糊页签；最低兼容与目标行为版本继续为 HarmonyOS 6.0.0 / API 20，没有为了新材质抬高系统要求。

| 运行系统与窗口 | 使用的组件和效果 | 兼容边界 |
| --- | --- | --- |
| API 23 及以上，所有窗口尺寸 | 同一个 NativeFloatingTabs / HdsTabs 实例始终采用底部 barFloatingStyle 官方悬浮圆角样式；不设置 barWidth、barHeight，由官方组件按断点适配几何；systemMaterialEffect 的 MaterialType 与 MaterialLevel 均为 ADAPTIVE，thermoCtrl 为 true | 悬浮样式与 hdsMaterial 起始为 HarmonyOS 6.1.0 / API 23；材质强度由系统策略、设备能力和温控控制；宽窄切换不销毁子页 |
| API 20～22，窗口宽度小于 840vp | 原生 TabsOptions.barModifier 接收 CommonModifier，设置圆角与悬浮间距；以实测窗口宽度减 32vp 得到页签宽度，保留两侧间距；Tabs.barOverlap 配合 barBackgroundBlurStyle(COMPONENT_REGULAR) | 提供本系统支持的原生圆角背景模糊；不加载 API 23 材质模块，也不宣称获得 API 23 沉浸光感 |
| API 20～22，窗口宽度达到 840vp | 同一个原生 Tabs 实例改为纵向侧栏，显式恢复圆角、间距、裁剪及模糊属性 | 宽窗口使用侧边导航，不强制套用底部 Dock |

新分支依据官方 [HdsTabs](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs) 与 [hdsMaterial](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsmaterial) 接口。起始版本同时核对本机官方 SDK 的 HdsTabsFloatingStyle、barFloatingStyle 与 hdsMaterial 声明，均标为 6.1.0(23)。API 20～22 的分支使用系统 Tabs 属性，圆角、模糊和页签交互仍由 ArkUI 绘制。

NativeFloatingTabs.ets 独立封装新组件及材质导入。Index.ets 对这个**本地模块**使用 import lazy，只有 sdkApiVersion >= 23 时才引用组件；组件内部也保留版本守卫。系统版本决定稳定的组件分支：API 23 起固定使用底部 NativeFloatingTabs / HdsTabs，API 20～22 固定使用 Tabs；仅后者随窗口修改同一实例的 vertical、页签位置及相应样式。两者均避免旋转或分屏时销毁子页，保留历史筛选、时间轴选择与下载任务。它按 [官方 lazy import 说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V13/arkts-lazy-import-V13) 延迟本地模块执行，不直接对 Kit 使用 lazy，也不通过其他普通导入提前加载同一模块。只在控件 build 内检查版本、却在入口普通导入新 Kit，不能替代此加载隔离。

API 23 分支不在侧栏与底栏之间切换形态，也不手动覆盖 HdsTabs 的宽高，以避免原生悬浮背景与页签几何错位。宽屏只调整内容网格，页签几何交给官方组件的断点适配。

本项目不自绘玻璃面板，不添加自定义着色器，也不对截屏或视频位图做模糊来模拟材质。API 23 分支交给 UI Design Kit；较旧系统交给 ArkUI 背景模糊。原生页签继续提供图标、标签、选中态和点击行为，主题仍使用浅色、深色、跟随系统三态。

Dock 与主内容采用重叠布局，使滚动内容可以经过系统材质下方。List 通过 contentEndOffset 增加可滚动末端空间，Scroll 在内容容器增加底部 padding，而不是把整个列表裁短到 Dock 上方。API 23 起所有窗口尺寸均向主页面传入 96vp 的底部补偿，并叠加原页面留白；API 20～22 仅窄窗口加入这份补偿，宽屏侧栏模式设为 0。末端空间使最后一张卡片或最后一个入口可滚动至 Dock 上方操作。

本节记录实现与兼容设计。深浅色截图、内容经过材质的效果、末项可达性以及窗口切换，应以实际视觉检查记录为准；编译成功不代替这些验收，也不代表 API 20～22 真机已经实测。

## 页面与原生组件映射

| 功能 | 原生组件 / API | 实现 |
| --- | --- | --- |
| 导航、返回、标题、菜单 | Navigation、NavPathStack、NavDestination、SymbolGlyphModifier | pages/Index.ets |
| 全局页签 | API 23 起所有尺寸固定 HdsTabs 底部悬浮，由官方断点适配几何；API 20～22 原生 Tabs 在窄屏悬浮页签与宽屏侧栏间切换；共用 TabContent、BottomTabBarStyle | pages/Index.ets、ui/NativeFloatingTabs.ets |
| 五路视频墙 | Grid、GridItem、Image、ImageKit PixelMap | ui/LivePage.ets、CameraPreview.ets |
| 通道详情与子页签 | Flex、Stack、Tabs、SubTabBarStyle | ui/ChannelPage.ets |
| 历史、事件卡片 | List、ListItem、LazyForEach、Image | ui/HistoryPage.ets |
| 通道、日期、类别、介质、分段 | Select | 历史与设置页面 |
| 通道全天时间选择 | 原生 Scroll / Scroller、固定游标、Canvas 可见色带、DatePickerDialog、Select 概览/精细 | ui/DayTimeline.ets、ChannelPage.ets |
| MP4 播放与控制 | Video、VideoController、原生控制条 | 全局 PlaybackPage.ets，通道原位 TimelinePlayer.ets |
| 设置分类及表单 | List、Button、TextInput、Toggle、Checkbox | SettingsPage.ets、ChannelSettingsPage.ets |
| 外观单选 | Radio | ui/SettingsPage.ets |
| 批量目标确认 | UIContext.showAlertDialog | ui/ChannelSettingsPage.ets |
| 日志、录像保存 | Core File Kit DocumentViewPicker.save | media/NativeDownloader.ets |

播放器保留 Video 原生控制条进行暂停、拖动和全屏，通过控制器回调同步媒体状态，与华为 [Video 使用指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V13/arkts-common-components-video-player-V13) 的基础使用方式一致。文件保存交给官方 [DocumentViewPicker](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-file-picker)，由用户选择目标位置。

## 信息层级与状态

实时页优先显示真实视频与在线/录像状态，设备摘要位于上方。只有有信号的通道建立预览连接，其他卡片独立显示状态；未知指标显示“—”，不填充演示数据、不将 CPU 百分比换算为功耗。

点通道先进入详情，浏览本路历史；全屏为独立动作。全局设置显示分类入口，通道参数从本通道右上菜单进入。

事件在截图下用圆点和文字共同标识：停留红色、人蓝色、车紫色、动物绿色。颜色不是唯一信息，图片容器保持中性，不绘制大面积类别边框。

表单使用有名称的原生控件，主要保存按钮高 48vp。忙碌时禁用重复提交，错误保留在当前页面并允许修正输入。批量应用先展示目标清单，加入待保存后才一起提交。

原生文字使用系统字体，通用导航图标使用系统符号。页面由 ArkUI 构成，视频帧由 ImageKit 解码，MP4 使用系统播放器，没有嵌入网页作为界面。

## 布局与主题边界

窄窗口采用两列实时卡片，内容宽度达到阈值时采用三列；宽窗口事件用两列。API 23 起始终使用底部悬浮页签，API 20～22 才在宽屏采用侧栏；悬浮效果按上表区分 API 23 材质与 API 20～22 原生模糊。详情在宽屏或较矮横屏下左右排布。设置内容限制最大宽度并顶部对齐。布局依据窗口尺寸，不按设备型号硬编码。

Theme.ets 统一背景、卡片、文字、辅助文字、分隔线和品牌色；base/element/color.json 与 dark/element/color.json 分别提供浅深值。视频自身和黑色播放器背景保留媒体表达，类别颜色维持稳定语义；切换外观不写板端设置。

主题 Radio 和整行点击共用同一选择入口：已选模式不重复写入，新的选择合并为一次延后任务，避开控件重建期间修改界面状态。任务执行与保存完成时均检查页面仍然挂载、请求代次、设备地址和设置分类；离页或分类改变时撤销尚未开始的选择任务。

当前设计只展示后端实际数据。全局列表仍只有最近 200 条，通道独立全天索引明确标识可播放范围与空白。时间轴使用手机当前时区定义所选自然日，刻度标出时区；DST 日按实际 23/25 小时展开，重复小时带时区标识。停止滚动后才提交选时，缩放和旋转保留时刻，原生播放器也限制在所选日期内。五路实机帧率、API 20 真机、字体放大和各类分屏的验收需依据实际测试分别记录。

</details>
