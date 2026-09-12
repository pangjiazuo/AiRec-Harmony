import { BusinessError } from '@kit.BasicServicesKit';
import { TimelinePlayback } from '../model/Timeline';
import { Palette } from './Theme';

/** 通道内只负责原生播放和定位；下载仍由全局回放页负责。 */
@Component
export struct TimelinePlayer {
  @Prop @Watch('requestChanged') request: TimelinePlayback = { url: '', position: 0, serial: 0, minPosition: 0, maxPosition: Number.MAX_SAFE_INTEGER };
  @Prop @Watch('activityChanged') active: boolean = true;
  onTime: (seconds: number) => void = (_: number): void => {};
  onEnded: () => void = (): void => {};
  onFullscreenChanged: (fullscreen: boolean) => void = (_: boolean): void => {};
  onExitFullscreenReady: (exit: () => void) => void = (_: () => void): void => {};
  @State private source: string = '';
  @State private errorText: string = '';
  private controller: VideoController = new VideoController();
  private mounted: boolean = false;
  private prepared: boolean = false;
  private restoring: boolean = false;
  private pending: number = 0;
  private duration: number = NaN;
  private wantsPlay: boolean = true;
  private playing: boolean = false;
  private ignorePause: boolean = false;
  private latestPosition: number = 0;
  private retry: number = 0;
  private retryTimer: number = -1;
  private seekTimer: number = -1;
  private logicalUrl: string = '';
  private loadGeneration: number = 0;
  private handledSerial: number = -1;
  private clampInFlight: boolean = false;
  private ended: boolean = false;

  aboutToAppear(): void {
    this.mounted = true; this.requestChanged();
    this.onExitFullscreenReady((): void => { if (this.mounted) this.controller.exitFullscreen(); });
  }
  aboutToDisappear(): void { this.mounted = false; this.clearRetry(); this.clearSeekTimer(); this.controller.stop(); this.onFullscreenChanged(false); }
  private clearRetry(): void { if (this.retryTimer >= 0) clearTimeout(this.retryTimer); this.retryTimer = -1; }
  private clearSeekTimer(): void { if (this.seekTimer >= 0) clearTimeout(this.seekTimer); this.seekTimer = -1; }
  private watchSeek(): void {
    this.clearSeekTimer();
    if (!this.restoring || !this.active || !this.wantsPlay) return;
    this.seekTimer = setTimeout((): void => {
      this.seekTimer = -1;
      if (!this.mounted || !this.active || !this.wantsPlay || !this.restoring) return;
      this.ignorePause = true; this.controller.pause(); this.prepared = false; this.playing = false; this.restoring = false;
      this.errorText = '录像定位未完成，正在尝试恢复'; this.scheduleRetry();
    }, 8000);
  }
  private scheduleRetry(): void {
    this.clearRetry();
    if (!this.mounted || !this.active || !this.wantsPlay || this.retry >= 5) return;
    const serial = this.request.serial;
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      if (this.mounted && this.active && this.wantsPlay && this.request.serial === serial) this.retryPlayback();
    }, Math.min(30000, 3000 * Math.pow(2, this.retry)));
  }
  private requestChanged(): void {
    if (!this.mounted) return;
    // 父页时钟更新不应重新定位；同一时刻的再次手势则有新的 serial。
    if (this.handledSerial === this.request.serial && this.logicalUrl === this.request.url) return;
    this.handledSerial = this.request.serial;
    this.clearRetry(); this.clearSeekTimer(); this.retry = 0;
    this.errorText = ''; this.pending = Math.max(this.request.minPosition, this.request.position); this.wantsPlay = true;
    this.clampInFlight = false; this.ended = false;
    const same = this.logicalUrl === this.request.url; this.logicalUrl = this.request.url;
    if (same && this.prepared) this.seek();
    else {
      this.prepared = false; this.playing = false; this.restoring = false; this.duration = NaN;
      this.latestPosition = this.pending; this.reloadSource();
    }
  }
  private reloadSource(): void {
    this.loadGeneration++;
    // 出错后重选同一片段也要改变实际 src，确保原生 Video 重新准备。
    this.source = `${this.logicalUrl}${this.logicalUrl.includes('?') ? '&' : '?'}recorder_client_reload=${this.loadGeneration}`;
  }
  private activityChanged(): void {
    if (!this.mounted) return;
    if (!this.active) {
      this.clearRetry(); this.clearSeekTimer();
      if (this.playing) { this.ignorePause = true; this.controller.pause(); }
    } else if (this.errorText) this.scheduleRetry();
    else this.play();
  }
  private play(): void {
    if (this.mounted && this.active && this.prepared && this.wantsPlay && !this.errorText) { this.watchSeek(); this.controller.start(); }
  }
  private seek(): void {
    this.pending = this.allowedPosition(this.pending);
    this.latestPosition = this.pending;
    this.restoring = true; this.controller.setCurrentTime(this.pending, SeekMode.Accurate);
    // 程序定位不会触发进度条的 onSeeked；按意图开播，由 onUpdate 确认新位置。
    this.play();
  }
  private allowedPosition(value: number): number {
    const end = Number.isFinite(this.duration) ? Math.min(this.duration, this.request.maxPosition) : this.request.maxPosition;
    return Math.max(this.request.minPosition, Math.min(value, Math.max(this.request.minPosition, end - 0.05)));
  }
  private constrainSeek(value: number): boolean {
    const safe = this.allowedPosition(value);
    this.latestPosition = safe;
    if (Math.abs(safe - value) <= 0.025) return false;
    if (!this.clampInFlight) {
      this.clampInFlight = true; this.pending = safe; this.seek();
    }
    return true;
  }
  private retryPlayback(): void {
    if (!this.mounted || !this.active) return;
    this.clearRetry(); this.clearSeekTimer();
    this.pending = this.latestPosition; this.prepared = false; this.restoring = false; this.errorText = ''; this.retry++;
    this.reloadSource();
  }
  private finish(): void {
    if (!this.mounted || !this.active || this.ended) return;
    this.ended = true; this.playing = false; this.wantsPlay = false; this.clearRetry(); this.clearSeekTimer();
    this.controller.pause(); this.onEnded();
  }
  build() {
    Column({ space: 8 }) {
      Video({ src: this.source, controller: this.controller, posterOptions: { showFirstFrame: true } })
        .width('100%').aspectRatio(16 / 9).objectFit(ImageFit.Contain).autoPlay(false).controls(true).loop(false)
        .backgroundColor('#000000').borderRadius(16).clip(true).id('channel-playback-video')
        .onPrepared((info: PreparedInfo): void => {
          if (!this.mounted) return;
          this.duration = info.duration; this.prepared = true; this.errorText = '';
          if (!Number.isFinite(info.duration) || this.request.minPosition >= info.duration) {
            this.prepared = false; this.wantsPlay = false; this.errorText = '录像实际时长与时间轴不一致，请刷新或选择其他时段'; return;
          }
          if (this.pending > 0.05) this.seek(); else this.play();
        })
        .onSeeked((info: PlaybackInfo): void => {
          if (!this.mounted || !this.prepared) return;
          this.clampInFlight = false;
          if (Number.isFinite(info.time) && this.constrainSeek(info.time)) return;
          const restoring = this.restoring; this.restoring = false; this.clearSeekTimer();
          if (Number.isFinite(info.time)) { this.latestPosition = info.time; this.onTime(info.time); }
          if (restoring) this.play();
        })
        .onSeeking((info: PlaybackInfo): void => {
          if (this.mounted && this.prepared && Number.isFinite(info.time)) this.constrainSeek(info.time);
        })
        .onUpdate((info: PlaybackInfo): void => {
          if (this.mounted && this.prepared && this.active && Number.isFinite(info.time)) {
            if (this.restoring) {
              // 原生回调按整秒上报，丢弃 seek 前排队的旧进度。
              if (info.time < Math.floor(this.pending) || info.time > this.pending + 3) return;
              this.restoring = false; this.clampInFlight = false; this.clearSeekTimer();
            }
            if (info.time < Math.floor(this.request.minPosition)) { this.pending = this.request.minPosition; this.seek(); return; }
            if (info.time >= this.request.maxPosition) { this.finish(); return; }
            this.latestPosition = Math.max(this.request.minPosition, info.time); this.retry = 0; this.onTime(this.latestPosition);
          }
        })
        .onStart((): void => {
          if (!this.mounted) return; this.playing = true;
          if (!this.active) { this.ignorePause = true; this.controller.pause(); } else this.wantsPlay = true;
        })
        .onPause((): void => {
          const wasPlaying = this.playing;
          this.playing = false;
          if (this.ignorePause) this.ignorePause = false;
          else if (wasPlaying && this.active && this.prepared) { this.wantsPlay = false; this.clearSeekTimer(); }
        })
        .onFinish((): void => this.finish())
        .onError((error: BusinessError): void => {
          if (!this.mounted) return;
          this.clearSeekTimer();
          this.prepared = false; this.playing = false; this.restoring = false; this.clampInFlight = false;
          this.errorText = `播放中断（${error.code}），请检查网络或刷新时间轴确认录像仍可用。`;
          this.scheduleRetry();
        })
        .onFullscreenChange((info: FullscreenInfo): void => { if (this.mounted) this.onFullscreenChanged(info.fullscreen); });
      if (this.errorText) {
        Text(this.errorText).fontSize(13).fontColor(Palette.secondary).width('100%');
        Button('重试播放').enabled(this.active).onClick((): void => this.retryPlayback()).id('channel-playback-retry');
      }
    }.width('100%');
  }
}
