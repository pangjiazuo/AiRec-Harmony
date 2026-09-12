import { RecorderApi } from '../data/RecorderApi';
import { RecordingItem } from '../model/Models';
import { TimelinePlayback, localDay, emptyTimeline, recordingAt, recordingStart,
  recordingEnd, continuation, clockText, timezoneText } from '../model/Timeline';
import { RecorderState } from './RecorderState';
import { CameraPreview } from './CameraPreview';
import { HistoryPage, PlaybackRequest } from './HistoryPage';
import { DayTimeline } from './DayTimeline';
import { TimelinePlayer } from './TimelinePlayer';
import { TimelineState } from './TimelineState';
import { Palette, metric, dayKey, eventColor } from './Theme';

const SCALES: SelectOption[] = [{ value: '概览' }, { value: '精细' }];

@Component
export struct ChannelPage {
  @ObjectLink @Watch('stateChanged') state: RecorderState;
  @Prop channelId: number = 1;
  onFullscreen: () => void = (): void => {};
  onImage: (url: string) => void = (_: string): void => {};
  onFullscreenChanged: (fullscreen: boolean) => void = (_: boolean): void => {};
  onExitFullscreenReady: (exit: () => void) => void = (_: () => void): void => {};
  @State private contentWidth: number = 400;
  @State private contentHeight: number = 800;
  @State private section: number = 0;
  @State private zoomIndex: number = 0;
  @State private timeline: TimelineState = new TimelineState(emptyTimeline(localDay(new Date())));
  @State private selectedAt: number = Date.now();
  @State private loaded: boolean = false;
  @State private busy: boolean = false;
  @State private message: string = '';
  @State private playbackMessage: string = '';
  @State private live: boolean = true;
  @State private scrubbing: boolean = false;
  @State private playback: TimelinePlayback = { url: '', position: 0, serial: 0, minPosition: 0, maxPosition: Number.MAX_SAFE_INTEGER };
  private current?: RecordingItem = undefined;
  private api?: RecorderApi = undefined;
  private mounted: boolean = false;
  private wasActive: boolean = false;
  private endpoint: string = '';
  private generation: number = 0;
  private timer: number = -1;

  aboutToAppear(): void { this.mounted = true; this.endpoint = this.state.endpoint; this.stateChanged(); }
  aboutToDisappear(): void { this.mounted = false; this.cancel(); }
  private active(): boolean { return this.state.foreground && this.state.route === `channel-${this.channelId}`; }
  private cancel(): void {
    this.generation++; this.api?.cancelAll(); this.api = undefined;
    if (this.timer >= 0) clearTimeout(this.timer); this.timer = -1; this.busy = false;
  }
  private stateChanged(): void {
    if (!this.mounted) return;
    if (this.endpoint !== this.state.endpoint) {
      this.endpoint = this.state.endpoint; this.returnLive(); this.loaded = false;
      this.timeline = new TimelineState(emptyTimeline(localDay(new Date()))); this.selectedAt = Date.now(); this.wasActive = false; this.cancel();
    }
    const active = this.active();
    if (active === this.wasActive) return;
    this.wasActive = active; this.cancel();
    if (active && this.section === 0) this.load(this.generation);
  }
  private changeSection(index: number): void {
    if (this.section === index) return;
    this.section = index; this.cancel();
    if (index === 0 && this.active()) this.load(this.generation);
  }
  private async load(generation: number): Promise<void> {
    if (!this.mounted || !this.active() || this.section !== 0 || generation !== this.generation) return;
    if (this.scrubbing) { this.timer = setTimeout((): void => { this.load(generation); }, 1000); return; }
    this.busy = true; this.api = this.state.api();
    try {
      const result = await this.api.getTimeline(this.channelId, this.timeline.window);
      if (generation !== this.generation || !this.mounted) return;
      if (!this.scrubbing) {
        this.timeline = new TimelineState(result); this.loaded = true; this.message = '';
        if (this.current && !result.recordings.some((item: RecordingItem): boolean => item.id === this.current?.id && item.available)) {
          this.stopPlayback('所选录像已不可用，请重新选择时间');
        }
      }
    } catch (error) {
      if (generation === this.generation) this.message = `${(error as Error).message || '时间轴暂时无法加载'}。可刷新重试。`;
    } finally {
      if (generation === this.generation) {
        this.busy = false;
        if (this.mounted && this.active() && this.section === 0) {
          this.timer = setTimeout((): void => { this.load(generation); }, this.loaded ? 15000 : 5000);
        }
      }
    }
  }
  private changeDate(date: Date): void {
    if (!this.mounted) return;
    const window = localDay(date);
    if (window.startMs === this.timeline.window.startMs) return;
    this.cancel(); this.returnLive(); this.loaded = false; this.message = '';
    this.timeline = new TimelineState(emptyTimeline(window));
    this.selectedAt = Date.now() >= window.startMs && Date.now() < window.endMs ? Date.now() : window.startMs;
    if (this.active() && this.section === 0) this.load(this.generation);
  }
  private chooseDate(): void {
    this.getUIContext().showDatePickerDialog({ selected: new Date(this.timeline.window.startMs),
      start: new Date(1970, 0, 1), end: new Date(),
      onDateAccept: (date: Date): void => { if (this.active()) this.changeDate(date); } });
  }
  private selectTime(at: number): void {
    if (!this.active() || !this.loaded) return;
    this.selectedAt = Math.max(this.timeline.window.startMs, Math.min(this.timeline.window.endMs, at));
    const item = recordingAt(this.timeline, this.selectedAt);
    if (!item) {
      this.stopPlayback(this.selectedAt >= this.timeline.window.endMs ? '已到当天 24:00，请选择其他时间或日期' : '该时段暂无可用录像');
      return;
    }
    this.playItem(item, this.selectedAt);
  }
  private playItem(item: RecordingItem, at: number): void {
    this.current = item; this.live = false; this.playbackMessage = '';
    this.playback = { url: this.state.api().mediaUrl(item.url), position: Math.max(0, (at - recordingStart(item)) / 1000),
      serial: this.playback.serial + 1, minPosition: Math.max(0, (this.timeline.window.startMs - recordingStart(item)) / 1000),
      maxPosition: Math.min(item.duration_seconds, (this.timeline.window.endMs - recordingStart(item)) / 1000) };
  }
  private stopPlayback(message: string): void {
    this.current = undefined; this.live = false; this.playbackMessage = message;
    this.playback = { url: '', position: 0, serial: this.playback.serial + 1, minPosition: 0, maxPosition: Number.MAX_SAFE_INTEGER };
  }
  private returnLive(): void {
    this.current = undefined; this.live = true; this.playbackMessage = '';
    this.playback = { url: '', position: 0, serial: this.playback.serial + 1, minPosition: 0, maxPosition: Number.MAX_SAFE_INTEGER };
  }
  private playbackTime(seconds: number): void {
    if (!this.current || this.scrubbing || !this.active()) return;
    const at = recordingStart(this.current) + seconds * 1000;
    this.selectedAt = Math.max(this.timeline.window.startMs, Math.min(this.timeline.window.endMs, at));
    if (at >= this.timeline.window.endMs) this.stopPlayback('已到当天 24:00，请选择其他日期');
  }
  private playbackEnded(): void {
    if (!this.current) { this.stopPlayback('关联录像播放完毕'); return; }
    const end = recordingEnd(this.current); const next = continuation(this.timeline, this.current);
    this.selectedAt = Math.min(end, this.timeline.window.endMs);
    if (next) this.playItem(next, end);
    else this.stopPlayback(end >= this.timeline.window.endMs ? '已到当天 24:00，请选择其他日期' : '后续时段暂无可用录像');
  }
  private eventPlayback(request: PlaybackRequest): void {
    this.current = undefined; this.live = false; this.playbackMessage = '事件关联录像';
    this.playback = { url: request.url, position: request.position, serial: this.playback.serial + 1,
      minPosition: 0, maxPosition: Number.MAX_SAFE_INTEGER };
  }
  private wide(): boolean { return this.contentWidth >= 840 || (this.contentWidth > this.contentHeight && this.contentHeight < 600); }

  @Builder private legend(label: string, type: string) {
    Row({ space: 4 }) {
      Row().width(6).height(6).borderRadius(3).backgroundColor(eventColor(type));
      Text(label).fontSize(11).fontColor(Palette.secondary);
    }
  }
  @Builder private dayPlayback() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Button(dayKey(this.timeline.window.start), { type: ButtonType.Normal }).fontSize(15)
          .backgroundColor(Color.Transparent).fontColor(Palette.text).onClick((): void => this.chooseDate()).id('timeline-date');
        Blank();
        Select(SCALES).selected(this.zoomIndex).value(SCALES[this.zoomIndex].value)
          .onSelect((index: number): void => { this.zoomIndex = index; }).id('timeline-scale');
        Button('刷新', { type: ButtonType.Normal }).backgroundColor(Color.Transparent).fontColor(Palette.brand)
          .enabled(!this.busy).onClick((): void => { this.cancel(); this.load(this.generation); }).id('timeline-refresh');
      }.width('100%');
      Row({ space: 10 }) { this.legend('录像', 'person'); this.legend('停留', 'dwell'); this.legend('人', 'person'); this.legend('车', 'vehicle'); this.legend('动物', 'animal'); }
        .width('100%');
      Text(`上下滑动选时 · ${timezoneText(this.selectedAt >= this.timeline.window.endMs ? this.selectedAt - 1 : this.selectedAt)} · 出现为细标记`)
        .fontSize(11).fontColor(Palette.secondary).width('100%');
      if (this.message) { Text(this.message).fontSize(12).fontColor(Palette.secondary).width('100%').id('timeline-error'); }
      if (this.loaded) {
        DayTimeline({ data: this.timeline, selectedAt: this.selectedAt, active: this.active() && this.section === 0,
          hourHeight: this.zoomIndex === 0 ? 240 : 1200,
          onCursor: (at: number): void => { this.selectedAt = at; }, onSelect: (at: number): void => this.selectTime(at),
          onScrubbing: (value: boolean): void => { this.scrubbing = value; } }).layoutWeight(1);
      } else {
        Column({ space: 12 }) {
          if (this.busy) { LoadingProgress().width(32).height(32); }
          Text(this.busy ? '正在加载当天完整时间轴…' : '时间轴尚未加载').fontSize(14).fontColor(Palette.secondary);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      }
    }.width('100%').height('100%').padding({ left: 16, right: 16, bottom: 16 });
  }
  build() {
    Flex({ direction: this.wide() ? FlexDirection.Row : FlexDirection.Column }) {
      Column({ space: 8 }) {
        if (this.live) {
          Stack({ alignContent: Alignment.BottomEnd }) {
            CameraPreview({ url: this.state.api().mediaUrl(`/stream/${this.channelId}.mjpg`), channelName: this.state.channel(this.channelId).name,
              offlineMessage: this.state.previewMessage(this.channelId),
              online: this.state.connected && this.state.channel(this.channelId).state === 'online',
              active: this.active(), decodeWidth: 1280 });
            Button('全屏', { type: ButtonType.Capsule }).backgroundColor('#A6111318').fontColor('#FFFFFF').margin(12)
              .onClick(this.onFullscreen).id('channel-fullscreen');
          }.width('100%').borderRadius(20).clip(true);
        } else if (this.playback.url) {
          TimelinePlayer({ request: this.playback, active: this.active() && !this.scrubbing,
            onTime: (seconds: number): void => this.playbackTime(seconds), onEnded: (): void => this.playbackEnded(),
            onFullscreenChanged: this.onFullscreenChanged, onExitFullscreenReady: this.onExitFullscreenReady });
        } else {
          Column({ space: 8 }) {
            Text(clockText(this.selectedAt, this.timeline.window)).fontSize(24).fontColor(Palette.text);
            Text(this.playbackMessage).fontSize(14).fontColor(Palette.secondary).textAlign(TextAlign.Center);
          }.width('100%').aspectRatio(16 / 9).justifyContent(FlexAlign.Center).padding(16).backgroundColor(Palette.preview).borderRadius(20);
        }
        Row() {
          Text(this.live ? `实时 · ${metric(this.state.channel(this.channelId).preview_fps, ' fps')}` :
            `${this.current ? clockText(this.selectedAt, this.timeline.window) : this.playbackMessage || '录像回放'}`)
            .fontSize(13).fontColor(Palette.secondary).layoutWeight(1).maxLines(2);
          if (!this.live) {
            Button('返回实时', { type: ButtonType.Normal }).backgroundColor(Color.Transparent).fontColor(Palette.brand)
              .onClick((): void => this.returnLive()).id('channel-return-live');
          } else {
            Text(this.state.channel(this.channelId).recording ? '正在录像' : '未录像').fontSize(13).fontColor(Palette.secondary);
          }
        }.width('100%').height(40);
      }.width(this.wide() ? '48%' : '100%').padding(16).flexShrink(0);
      Column() {
        Tabs({ index: this.section }) {
          TabContent() {}.tabBar(new SubTabBarStyle('回放'));
          TabContent() {}.tabBar(new SubTabBarStyle('事件'));
        }.height(52).barHeight(48).animationDuration(0).onChange((index: number): void => this.changeSection(index)).id('channel-tabs');
        if (this.section === 0) { Column() { this.dayPlayback(); }.width('100%').layoutWeight(1); }
        else {
          HistoryPage({ state: this.state, kind: 'events', fixedChannel: this.channelId,
            active: this.active(), onPlay: (request: PlaybackRequest): void => this.eventPlayback(request), onImage: this.onImage }).layoutWeight(1);
        }
      }.width(this.wide() ? '52%' : '100%').layoutWeight(1);
    }.width('100%').height('100%').backgroundColor(Palette.background).id('channel-detail')
      .onAreaChange((_old: Area, area: Area): void => { this.contentWidth = Number(area.width); this.contentHeight = Number(area.height); });
  }
}
