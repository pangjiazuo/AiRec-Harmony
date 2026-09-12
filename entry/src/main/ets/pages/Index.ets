import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { SymbolGlyphModifier, window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { CommonModifier } from '@ohos.arkui.modifier';
import lazy { NativeFloatingTabs } from '../ui/NativeFloatingTabs';
import { PreferencesService } from '../data/PreferencesService';
import { AppearanceMode } from '../model/Models';
import { RecorderState, RouteData, routeData } from '../ui/RecorderState';
import { Palette } from '../ui/Theme';
import { LivePage, DevicePage } from '../ui/LivePage';
import { CameraPreview } from '../ui/CameraPreview';
import { ChannelPage } from '../ui/ChannelPage';
import { HistoryPage, PlaybackRequest } from '../ui/HistoryPage';
import { PlaybackPage } from '../ui/PlaybackPage';
import { SettingsPage } from '../ui/SettingsPage';
import { ChannelSettingsPage } from '../ui/ChannelSettingsPage';

@Entry
@Component
struct Index {
  @State private state: RecorderState = new RecorderState();
  @State private stack: NavPathStack = new NavPathStack();
  @State private tab: number = 0;
  @State private wide: boolean = false;
  @State private contentWidth: number = 360;
  @State private videoFullscreen: boolean = false;
  @StorageLink('recorderForeground') @Watch('foregroundChanged') foreground: boolean = true;
  private exitVideoFullscreen: () => void = () => {};
  private loaded: boolean = false;
  // 兼容 API 20～22：修饰系统 TabBar，圆角和模糊均由 ArkUI 绘制。
  private legacyDock: CommonModifier = new CommonModifier().borderRadius(32)
    .margin({ bottom: 12 }).clip(true);
  private sideBar: CommonModifier = new CommonModifier().borderRadius(0)
    .margin({ bottom: 0 }).clip(false);

  aboutToAppear(): void { this.initialize(); }
  aboutToDisappear(): void { this.state.stop(); }
  private async initialize(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const preferences = await PreferencesService.load(context);
      this.state.endpoint = preferences.endpoint; this.state.appearance = preferences.appearance;
      this.applyAppearance(preferences.appearance);
    } catch (error) { /* 偏好读取失败不影响默认局域网连接。 */ }
    this.loaded = true;
    if (this.foreground) this.state.start();
  }
  private applyAppearance(mode: AppearanceMode): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.getApplicationContext().setColorMode(mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      mode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }
  private foregroundChanged(): void { if (this.loaded) { if (this.foreground) this.state.start(); else this.state.stop(); } }
  private homeRoute(): string { return ['live', 'recordings', 'events', 'settings'][this.tab]; }
  private homeTitle(): string { return ['录像机', '录像回放', '智能事件', '设置'][this.tab]; }
  private bottomInset(): number { return this.wide && deviceInfo.sdkApiVersion < 23 ? 0 : 96; }
  private open(name: string, data: RouteData = routeData()): void { this.stack.pushPath({ name, param: data }); }
  private play(request: PlaybackRequest): void {
    this.open('playback', routeData(0, request.url, request.title, request.position, request.recordedAt));
  }
  private openSettings(category: string): void {
    const names: Record<string, string> = { 'connection': '设备连接', 'storage': '录像存储', 'model': '识别模型', 'logs': '日志与诊断', 'appearance': '外观与显示' };
    this.open('settings-section', routeData(0, category, names[category] || '设置'));
  }
  private endpointChanged(endpoint: string): void {
    // 更换设备后销毁原设备页面和草稿，避免误保存到另一台录像机。
    this.stack.clear(); this.tab = 0; this.state.route = 'live'; this.state.connect(endpoint);
  }
  private bars(visible: boolean): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(context).then((main: window.Window) => {
      main.setWindowSystemBarEnable(visible ? ['status', 'navigation'] : []).catch(() => {});
      main.setWindowKeepScreenOn(!visible).catch(() => {});
    }).catch(() => {});
  }

  @Builder private destination(name: string, value: Object) {
    if (name === 'channel') {
      NavDestination() {
        ChannelPage({ state: this.state, channelId: (value as RouteData).channel,
          onFullscreen: () => this.open('fullscreen', value as RouteData),
          onImage: (url: string) => this.open('image', routeData(0, url)),
          onFullscreenChanged: (fullscreen: boolean): void => { this.videoFullscreen = fullscreen; },
          onExitFullscreenReady: (exit: () => void): void => { this.exitVideoFullscreen = exit; } });
      }.title(this.state.channel((value as RouteData).channel).name)
        .hideTitleBar(this.videoFullscreen)
        .menus([{ value: '通道设置', symbolIcon: new SymbolGlyphModifier($r('sys.symbol.gearshape')),
          action: () => this.open('channel-settings', value as RouteData) }])
        .onShown(() => { this.state.route = `channel-${(value as RouteData).channel}`; })
        .onBackPressed(() => { if (this.videoFullscreen) { this.exitVideoFullscreen(); return true; } return false; });
    } else if (name === 'channel-settings') {
      NavDestination() { ChannelSettingsPage({ state: this.state, channelId: (value as RouteData).channel }); }
        .title(`${this.state.channel((value as RouteData).channel).name} 设置`).onShown(() => { this.state.route = 'channel-settings'; });
    } else if (name === 'device') {
      NavDestination() { DevicePage({ state: this.state }); }.title('设备信息').onShown(() => { this.state.route = 'device'; });
    } else if (name === 'settings-section') {
      NavDestination() {
        SettingsPage({ state: this.state, category: (value as RouteData).url, onOpen: (category: string) => this.openSettings(category),
          onEndpointChanged: (endpoint: string) => this.endpointChanged(endpoint) });
      }.title((value as RouteData).title).onShown(() => { this.state.route = `settings-${(value as RouteData).url}`; });
    } else if (name === 'playback') {
      NavDestination() {
        PlaybackPage({ state: this.state, url: (value as RouteData).url, title: (value as RouteData).title,
          initialPosition: (value as RouteData).position, recordedAt: (value as RouteData).recordedAt,
          onFullscreenChanged: (fullscreen: boolean) => { this.videoFullscreen = fullscreen; },
          onExitFullscreenReady: (exit: () => void) => { this.exitVideoFullscreen = exit; } });
      }.title('录像回放').hideTitleBar(this.videoFullscreen).onShown(() => { this.state.route = 'playback'; })
        .onBackPressed(() => { if (this.videoFullscreen) { this.exitVideoFullscreen(); return true; } return false; });
    } else if (name === 'image') {
      NavDestination() {
        Image((value as RouteData).url).width('100%').height('100%').objectFit(ImageFit.Contain).backgroundColor('#000000').accessibilityText('事件原图');
      }.title('事件截图').onShown(() => { this.state.route = 'image'; });
    } else if (name === 'fullscreen') {
      NavDestination() {
        Stack({ alignContent: Alignment.Center }) {
          CameraPreview({ url: this.state.api().mediaUrl(`/stream/${(value as RouteData).channel}.mjpg`),
            channelName: this.state.channel((value as RouteData).channel).name,
            offlineMessage: this.state.previewMessage((value as RouteData).channel),
            online: this.state.connected && this.state.channel((value as RouteData).channel).state === 'online',
            active: this.state.foreground && this.state.route === 'fullscreen', decodeWidth: 1280 });
          Button('退出全屏', { type: ButtonType.Capsule }).backgroundColor('#A6333333').fontColor('#FFFFFF')
            .position({ x: 16, y: 16 }).onClick(() => this.stack.pop()).id('fullscreen-exit');
        }.width('100%').height('100%').backgroundColor('#000000');
      }.hideTitleBar(true).onShown(() => { this.state.route = 'fullscreen'; this.bars(false); }).onHidden(() => this.bars(true));
    }
  }

  @Builder private tabContents() {
    TabContent() {
      LivePage({ state: this.state, bottomInset: this.bottomInset(),
        onChannel: (id: number) => this.open('channel', routeData(id)), onDevice: () => this.open('device') });
    }.tabBar(new BottomTabBarStyle({ normal: new SymbolGlyphModifier($r('sys.symbol.video')) }, '实时')).id('nav-live');
    TabContent() {
      HistoryPage({ state: this.state, kind: 'recordings', active: this.state.foreground && this.state.route === 'recordings',
        bottomInset: this.bottomInset(),
        onPlay: (request: PlaybackRequest) => this.play(request) });
    }.tabBar(new BottomTabBarStyle({ normal: new SymbolGlyphModifier($r('sys.symbol.play')) }, '回放')).id('nav-recordings');
    TabContent() {
      HistoryPage({ state: this.state, kind: 'events', active: this.state.foreground && this.state.route === 'events',
        bottomInset: this.bottomInset(),
        onPlay: (request: PlaybackRequest) => this.play(request), onImage: (url: string) => this.open('image', routeData(0, url)) });
    }.tabBar(new BottomTabBarStyle({ normal: new SymbolGlyphModifier($r('sys.symbol.bell')) }, '事件')).id('nav-events');
    TabContent() {
      SettingsPage({ state: this.state, category: 'home', onOpen: (category: string) => this.openSettings(category),
        bottomInset: this.bottomInset(),
        onEndpointChanged: (endpoint: string) => this.endpointChanged(endpoint) });
    }.tabBar(new BottomTabBarStyle({ normal: new SymbolGlyphModifier($r('sys.symbol.gearshape')) }, '设置')).id('nav-settings');
  }

  build() {
    Navigation(this.stack) {
      if (deviceInfo.sdkApiVersion >= 23) {
        NativeFloatingTabs({ selectedIndex: this.tab, content: (): void => { this.tabContents(); },
          onSelect: (index: number) => { this.tab = index; this.state.route = this.homeRoute(); } });
      } else {
        Tabs({ barPosition: this.wide ? BarPosition.Start : BarPosition.End, index: this.tab,
          barModifier: this.wide ? this.sideBar : this.legacyDock }) {
          this.tabContents();
        }.vertical(this.wide).barWidth(this.wide ? 88 : Math.max(0, this.contentWidth - 32)).barHeight(this.wide ? '100%' : 64)
          .barOverlap(!this.wide)
          .barBackgroundColor(this.wide ? Palette.card : Color.Transparent)
          .barBackgroundBlurStyle(this.wide ? BlurStyle.NONE : BlurStyle.COMPONENT_REGULAR,
            { colorMode: ThemeColorMode.SYSTEM })
          .scrollable(false).animationDuration(180)
          .onChange((index: number) => { this.tab = index; this.state.route = this.homeRoute(); });
      }
    }.title(this.homeTitle()).titleMode(NavigationTitleMode.Mini).hideBackButton(true).mode(NavigationMode.Stack)
      .navDestination(this.destination).backgroundColor(Palette.background)
      .onNavBarStateChange((visible: boolean) => { if (visible) this.state.route = this.homeRoute(); })
      .onAreaChange((_old: Area, area: Area) => {
        this.contentWidth = Number(area.width); this.wide = this.contentWidth >= 840;
      });
  }
}
