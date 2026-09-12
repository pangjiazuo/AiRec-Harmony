import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NativeDownloader } from '../media/NativeDownloader';
import { RecorderState } from './RecorderState';
import { Palette, Notice, bytesText, dateText, pad } from './Theme';

/** 一个原生 Video 节点随布局调整尺寸，旋转不会创建第二个播放器。 */
@Component
export struct PlaybackPage {
  @ObjectLink @Watch('activityChanged') state: RecorderState;
  @Prop @Watch('sourceChanged') url: string = '';
  @Prop title: string = '';
  @Prop initialPosition: number = 0;
  @Prop recordedAt: string = '';
  onFullscreenChanged: (fullscreen: boolean) => void = (_: boolean): void => {};
  onExitFullscreenReady: (exit: () => void) => void = (_: () => void): void => {};
  @State private source: string = '';
  @State private layoutWidth: number = 400;
  @State private layoutHeight: number = 700;
  @State private duration: number = NaN;
  @State private playbackPosition: number = 0;
  @State private prepared: boolean = false;
  @State private playing: boolean = false;
  @State private errorMessage: string = '';
  @State private downloading: boolean = false;
  @State private downloadMessage: string = '';
  private controller: VideoController = new VideoController();
  private downloader: NativeDownloader = new NativeDownloader();
  private mounted: boolean = false;
  private wantsPlay: boolean = true;
  private ignoreNextPause: boolean = false;
  private lastForeground: boolean = true;
  private resumePosition: number = 0;
  private restoring: boolean = false;
  private seeking: boolean = false;
  private retryCount: number = 0;

  aboutToAppear(): void {
    this.mounted = true; this.lastForeground = this.state.foreground; this.sourceChanged();
    this.onExitFullscreenReady((): void => { if (this.mounted) this.controller.exitFullscreen(); });
  }
  aboutToDisappear(): void {
    this.mounted = false; this.downloader.cancel(); this.controller.stop();
    this.onFullscreenChanged(false);
  }
  private sourceChanged(): void {
    if (!this.mounted) return;
    this.prepared = false; this.duration = NaN; this.playbackPosition = 0; this.playing = false;
    this.wantsPlay = true; this.restoring = false; this.seeking = false; this.ignoreNextPause = false;
    this.resumePosition = Number.isFinite(this.initialPosition) ? Math.max(0, this.initialPosition) : 0;
    this.retryCount = 0; this.errorMessage = ''; this.source = this.url;
  }
  private activityChanged(): void {
    if (!this.mounted || this.lastForeground === this.state.foreground) return;
    this.lastForeground = this.state.foreground;
    if (!this.state.foreground) {
      if (this.playing) { this.ignoreNextPause = true; this.controller.pause(); }
    } else if (this.prepared && !this.restoring && this.wantsPlay && this.errorMessage.length === 0) {
      this.controller.start();
    }
  }
  private applyPlaybackIntent(): void {
    if (this.mounted && this.state.foreground && this.wantsPlay && this.prepared && !this.restoring) this.controller.start();
  }
  private preparedVideo(info: PreparedInfo): void {
    if (!this.mounted) return;
    this.duration = Number.isFinite(info.duration) && info.duration >= 0 ? info.duration : NaN;
    this.prepared = true; this.errorMessage = '';
    const seek = Number.isFinite(this.duration) ? Math.min(this.resumePosition, Math.max(0, this.duration - 0.1)) : this.resumePosition;
    if (seek > 0.05) {
      this.restoring = true; this.controller.setCurrentTime(seek, SeekMode.Accurate);
    } else { this.resumePosition = 0; this.playbackPosition = 0; this.applyPlaybackIntent(); }
  }
  private updatePosition(info: PlaybackInfo): void {
    if (!this.mounted || !this.prepared || this.restoring || this.seeking || !Number.isFinite(info.time)) return;
    this.playbackPosition = Math.max(0, info.time); this.resumePosition = this.playbackPosition;
  }
  private seekFinished(info: PlaybackInfo): void {
    if (!this.mounted || !this.prepared) return;
    const wasRestoring = this.restoring;
    this.restoring = false; this.seeking = false;
    if (Number.isFinite(info.time)) { this.playbackPosition = Math.max(0, info.time); this.resumePosition = this.playbackPosition; }
    if (wasRestoring) this.applyPlaybackIntent();
  }
  private retryPlayback(): void {
    if (!this.mounted || !this.state.foreground) return;
    this.prepared = false; this.playing = false; this.restoring = false; this.seeking = false;
    this.errorMessage = ''; this.retryCount++;
    // 只刷新同一媒体地址，待 onPrepared 后恢复最后一次原生回报的位置。
    this.source = `${this.url}${this.url.includes('?') ? '&' : '?'}recorder_retry=${this.retryCount}`;
  }
  private elapsed(seconds: number): string {
    if (!Number.isFinite(seconds)) return '--:--';
    const whole = Math.max(0, Math.floor(seconds));
    return whole >= 3600 ? `${pad(Math.floor(whole / 3600))}:${pad(Math.floor(whole / 60) % 60)}:${pad(whole % 60)}` :
      `${pad(Math.floor(whole / 60))}:${pad(whole % 60)}`;
  }
  private recordedTime(): string {
    if (!this.recordedAt) return '';
    const start = new Date(this.recordedAt).getTime();
    return Number.isFinite(start) ? dateText(new Date(start + this.playbackPosition * 1000).toISOString()) : '';
  }
  private wide(): boolean { return this.layoutWidth >= 720 || (this.layoutWidth >= 560 && this.layoutWidth > this.layoutHeight); }
  private videoWidth(): number {
    const available = Math.max(1, this.layoutWidth - 32);
    return this.wide() ? Math.min((available - 20) * 0.62, Math.max(120, this.layoutHeight - 32) * 16 / 9) : available;
  }
  private informationWidth(): number { return this.wide() ? Math.max(1, this.layoutWidth - 52 - this.videoWidth()) : Math.max(1, this.layoutWidth - 32); }
  private async downloadRecording(): Promise<void> {
    if (this.downloading) return;
    this.downloading = true; this.downloadMessage = '正在下载录像…';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await this.downloader.save(context, this.url, 'recording', this.title, (bytes: number): void => {
        if (this.mounted) this.downloadMessage = `已接收 ${bytesText(bytes)}`;
      });
      if (this.mounted) this.downloadMessage = result.saved ? `录像已保存 · ${bytesText(result.bytes)}` : '已取消保存';
    } catch (error) {
      if (this.mounted) this.downloadMessage = `下载未完成：${(error as Error).message || '请重试'}`;
    } finally { if (this.mounted) this.downloading = false; }
  }

  build() {
    Scroll() {
      Flex({ direction: this.wide() ? FlexDirection.Row : FlexDirection.Column, alignItems: ItemAlign.Start,
        justifyContent: FlexAlign.Start }) {
        Column() {
          Video({ src: this.source, controller: this.controller, posterOptions: { showFirstFrame: true } })
            .width('100%').aspectRatio(16 / 9).objectFit(ImageFit.Contain)
            .autoPlay(false).controls(true).loop(false).backgroundColor('#000000').borderRadius(12).clip(true)
            .id('playback-video')
            .onPrepared((info: PreparedInfo): void => this.preparedVideo(info))
            .onStart((): void => {
              if (!this.mounted) return;
              this.playing = true;
              if (this.state.foreground) this.wantsPlay = true;
              else { this.ignoreNextPause = true; this.controller.pause(); }
            })
            .onPause((): void => {
              if (!this.mounted) return;
              this.playing = false;
              if (this.ignoreNextPause) this.ignoreNextPause = false;
              else if (this.mounted && this.state.foreground && this.prepared && !this.restoring) this.wantsPlay = false;
            })
            .onFinish((): void => { if (!this.mounted) return; this.playing = false; this.wantsPlay = false; if (Number.isFinite(this.duration)) { this.playbackPosition = this.duration; this.resumePosition = this.duration; } })
            .onSeeking((): void => { if (this.mounted) this.seeking = true; })
            .onSeeked((info: PlaybackInfo): void => this.seekFinished(info))
            .onUpdate((info: PlaybackInfo): void => this.updatePosition(info))
            .onError((error: BusinessError): void => {
              if (!this.mounted) return;
              this.prepared = false; this.playing = false; this.restoring = false; this.seeking = false;
              this.errorMessage = `录像暂时无法播放（${error.code}）。请检查网络，或确认文件是否已被循环清理。`;
            })
            .onFullscreenChange((info: FullscreenInfo): void => { if (this.mounted) this.onFullscreenChanged(info.fullscreen); });
        }.width(this.videoWidth()).flexShrink(0);
        Column({ space: 16 }) {
          Column({ space: 12 }) {
            Text(this.title || '录像片段').fontSize(18).fontWeight(FontWeight.Medium).fontColor(Palette.text).width('100%');
            Text(this.prepared ? (this.playing ? '正在回放' : '已暂停') : (this.errorMessage ? '播放中断' : '正在准备录像…'))
              .fontSize(13).fontColor(Palette.secondary).width('100%');
            Row() {
              Text(this.elapsed(this.playbackPosition)).fontSize(20).fontColor(Palette.brand);
              Blank();
              Text(`/ ${this.elapsed(this.duration)}`).fontSize(14).fontColor(Palette.secondary);
            }.width('100%');
            if (this.recordedTime()) {
              Text(this.recordedTime()).fontSize(14).fontColor(Palette.secondary).width('100%');
            }
            Divider().color(Palette.line);
            Text('MP4 · 录像回放').fontSize(13).fontColor(Palette.secondary).width('100%');
          }.width('100%').padding(16).backgroundColor(Palette.card).borderRadius(12).border({ width: 0.5, color: Palette.line });
          if (this.errorMessage) {
            Notice({ text: this.errorMessage });
            Button('重试播放').width('100%').height(48).backgroundColor(Palette.brand)
              .enabled(this.state.foreground).onClick((): void => this.retryPlayback()).id('playback-retry');
          }
          Button(this.downloading ? '正在下载…' : '保存录像到设备').width('100%').height(48)
            .backgroundColor(Palette.brand).enabled(!this.downloading && this.url.length > 0)
            .onClick((): void => { this.downloadRecording(); }).id('playback-download');
          if (this.downloading) {
            Button('取消下载').width('100%').height(44).backgroundColor(Palette.card).fontColor(Palette.text)
              .onClick((): void => this.downloader.cancel()).id('playback-download-cancel');
          }
          Notice({ text: this.downloadMessage });
        }.width(this.informationWidth()).margin({ left: this.wide() ? 20 : 0, top: this.wide() ? 0 : 16 }).flexShrink(0);
      }.padding(16).width('100%');
    }.width('100%').height('100%').align(Alignment.TopStart).backgroundColor(Palette.background).id('playback-screen')
      .onAreaChange((_, area: Area): void => {
        this.layoutWidth = Number(area.width); this.layoutHeight = Number(area.height);
      });
  }
}
