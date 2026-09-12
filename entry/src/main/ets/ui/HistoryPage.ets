import { common } from '@kit.AbilityKit';
import { RecordingItem, EventItem } from '../model/Models';
import { RecorderApi } from '../data/RecorderApi';
import { NativeDownloader } from '../media/NativeDownloader';
import { RecorderState } from './RecorderState';
import { ArrayDataSource } from './ArrayDataSource';
import { Palette, Notice, bytesText, dateText, dayKey, eventName, eventColor } from './Theme';

export interface PlaybackRequest { url: string; title: string; position: number; recordedAt: string; }
const CHANNEL_OPTIONS: SelectOption[] = [{ value: '全部通道' }, { value: 'AHD1' }, { value: 'AHD2' },
  { value: 'AHD3' }, { value: 'AHD4' }, { value: 'AHD5' }];
const EVENT_OPTIONS: SelectOption[] = [{ value: '全部事件' }, { value: '长时间停留' }, { value: '人' }, { value: '车' }, { value: '动物' }];
const EVENT_TYPES: string[] = ['', 'dwell', 'person', 'vehicle', 'animal'];

@Component
export struct HistoryPage {
  @ObjectLink @Watch('deviceChanged') state: RecorderState;
  @Prop @Watch('reset') kind: string = 'recordings';
  @Prop fixedChannel: number = 0;
  @Prop bottomInset: number = 0;
  @Prop @Watch('activityChanged') active: boolean = true;
  onPlay: (request: PlaybackRequest) => void = () => {};
  onImage: (url: string) => void = () => {};
  @State private recordings: RecordingItem[] = [];
  @State private events: EventItem[] = [];
  @State private channel: number = 0;
  @State private eventIndex: number = 0;
  @State private selectedDate: string = '';
  @State private message: string = '';
  @State private busy: boolean = false;
  @State private downloading: boolean = false;
  @State private downloadMessage: string = '';
  @State private contentWidth: number = 400;
  private api: RecorderApi | undefined = undefined;
  private downloader: NativeDownloader = new NativeDownloader();
  private timer: number = -1;
  private generation: number = 0;
  private mounted: boolean = false;
  private loadedEndpoint: string = '';
  private recordingSource: ArrayDataSource<RecordingItem> = new ArrayDataSource<RecordingItem>();
  private eventSource: ArrayDataSource<EventItem> = new ArrayDataSource<EventItem>();

  aboutToAppear(): void { this.mounted = true; this.loadedEndpoint = this.state.endpoint; this.activityChanged(); }
  aboutToDisappear(): void { this.mounted = false; this.cancel(); this.downloader.cancel(); }
  private deviceChanged(): void {
    if (this.loadedEndpoint === this.state.endpoint) return;
    this.loadedEndpoint = this.state.endpoint; this.downloader.cancel(); this.downloadMessage = '';
    this.channel = 0; this.eventIndex = 0; this.reset();
  }
  private reset(): void {
    this.selectedDate = ''; this.recordings = []; this.events = [];
    this.recordingSource.replace([]); this.eventSource.replace([]); this.activityChanged();
  }
  private cancel(): void { this.generation++; this.api?.cancelAll(); if (this.timer >= 0) clearTimeout(this.timer); this.timer = -1; this.busy = false; }
  private activityChanged(): void { this.cancel(); if (this.active && this.mounted) this.load(this.generation); }
  private async load(generation: number): Promise<void> {
    this.busy = true;
    this.api = this.state.api();
    try {
      const channel = this.fixedChannel || this.channel;
      if (this.kind === 'events') {
        const result = await this.api.getEvents(channel || undefined, EVENT_TYPES[this.eventIndex] || undefined);
        if (generation !== this.generation) return;
        this.events = result;
        this.eventSource.replace(result);
      } else {
        const result = await this.api.getRecordings(channel || undefined);
        if (generation !== this.generation) return;
        this.recordings = result;
        const dates = this.dates();
        if (!dates.includes(this.selectedDate)) this.selectedDate = dates.length > 0 ? dates[0] : '';
        this.recordingSource.replace(this.visibleRecordings());
      }
      this.message = '';
    } catch (error) {
      if (generation === this.generation) this.message = '暂时无法加载记录，将自动重试。';
    } finally {
      if (generation === this.generation) {
        this.busy = false;
        if (this.active && this.mounted) this.timer = setTimeout(() => this.load(generation), 5000);
      }
    }
  }
  private dates(): string[] {
    const days: string[] = [];
    this.recordings.forEach((item: RecordingItem) => { const day = dayKey(item.created_at); if (day && !days.includes(day)) days.push(day); });
    return days.sort().reverse();
  }
  private visibleRecordings(): RecordingItem[] { return this.recordings.filter((item: RecordingItem) => dayKey(item.created_at) === this.selectedDate); }
  private play(item: RecordingItem, offset: number = 0): void {
    if (!item.available || !item.url) return;
    this.onPlay({ url: this.state.api().mediaUrl(item.url), title: `AHD${item.channel_id} · ${dateText(item.created_at)}`,
      position: offset, recordedAt: item.created_at });
  }
  private async download(item: RecordingItem): Promise<void> {
    if (this.downloading) return;
    this.downloading = true; this.downloadMessage = '正在下载录像…';
    try {
      const result = await this.downloader.save(this.getUIContext().getHostContext() as common.UIAbilityContext,
        this.state.api().mediaUrl(item.url), 'recording', `AHD${item.channel_id}-${item.created_at}.mp4`,
        (bytes: number) => { if (this.mounted) this.downloadMessage = `已下载 ${bytesText(bytes)}`; });
      if (this.mounted) this.downloadMessage = result.saved ? '录像已保存' : '已取消保存';
    } catch (error) { if (this.mounted) this.downloadMessage = `下载失败：${(error as Error).message}`; }
    finally { if (this.mounted) this.downloading = false; }
  }

  @Builder private recordingCard(item: RecordingItem) {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Text(`AHD${item.channel_id}`).fontSize(13).fontColor(Palette.brand);
        Text(dateText(item.created_at)).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Palette.text).layoutWeight(1).maxLines(1);
        Text('MP4').fontSize(12).fontColor(Palette.secondary);
      }.width('100%');
      Text(`${item.duration_seconds.toFixed(0)} 秒  ·  ${bytesText(item.size_bytes)}`).fontSize(14).fontColor(Palette.secondary).width('100%');
      if (!item.available) { Text('文件已被循环清理').fontSize(14).fontColor(Palette.secondary).width('100%'); }
      Row({ space: 12 }) {
        Button('播放录像').enabled(item.available).onClick(() => this.play(item)).id(`recording-play-${item.id}`);
        Blank();
        Button('下载', { type: ButtonType.Normal }).backgroundColor(Color.Transparent).fontColor(Palette.brand)
          .enabled(item.available && !this.downloading).onClick(() => this.download(item));
      }.width('100%');
    }.padding(20).width('100%').backgroundColor(Palette.card).borderRadius(24);
  }
  @Builder private eventCard(item: EventItem) {
    Column() {
      if (item.snapshot_url.length > 0) {
        Image(this.state.api().mediaUrl(item.snapshot_url)).width('100%').aspectRatio(16 / 9).objectFit(ImageFit.Contain)
          .backgroundColor('#111318').onClick(() => this.onImage(this.state.api().mediaUrl(item.snapshot_url)))
          .accessibilityText('事件截图').id(`event-image-${item.id}`);
      }
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Row().width(8).height(8).borderRadius(4).backgroundColor(eventColor(item.event_type));
          Text(eventName(item.event_type)).fontSize(17).fontWeight(FontWeight.Medium).fontColor(Palette.text);
          Blank(); Text(`AHD${item.channel_id}`).fontSize(13).fontColor(Palette.secondary);
        }.width('100%');
        Text(dateText(item.created_at)).fontSize(14).fontColor(Palette.secondary).width('100%');
        if (item.event_type === 'dwell') {
          Text(`停留 ${item.dwell_seconds.toFixed(1)} 秒`).fontSize(14).fontColor(Palette.secondary).width('100%');
        }
        if (item.recording_url && item.recording_available) {
          Button('查看关联录像', { type: ButtonType.Normal }).backgroundColor(Color.Transparent).fontColor(Palette.brand)
            .onClick(() => this.onPlay({ url: this.state.api().mediaUrl(item.recording_url), title: eventName(item.event_type), position: 0, recordedAt: '' }));
        } else { Text('暂无已完成的关联录像').fontSize(13).fontColor(Palette.secondary).width('100%'); }
      }.padding(20).width('100%');
    }.width('100%').backgroundColor(Palette.card).borderRadius(24).clip(true);
  }
  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        if (this.fixedChannel === 0) {
          Select(CHANNEL_OPTIONS).selected(this.channel).value(CHANNEL_OPTIONS[this.channel].value)
            .onSelect((index: number) => { this.channel = index; this.reset(); }).id('history-channel');
        }
        if (this.kind === 'events') {
          Select(EVENT_OPTIONS).selected(this.eventIndex).value(EVENT_OPTIONS[this.eventIndex].value)
            .onSelect((index: number) => { this.eventIndex = index; this.reset(); }).id('event-filter');
        } else if (this.dates().length > 0) {
          Select(this.dates().map((day: string): SelectOption => { return { value: day }; }))
            .value(this.selectedDate).selected(this.dates().indexOf(this.selectedDate))
            .onSelect((index: number) => {
              this.selectedDate = this.dates()[index];
              this.recordingSource.replace(this.visibleRecordings());
            }).id('recording-date');
        }
        Blank();
        Button('刷新', { type: ButtonType.Normal }).backgroundColor(Color.Transparent).fontColor(Palette.brand)
          .enabled(!this.busy).onClick(() => this.activityChanged());
      }.width('100%').padding({ left: 16, right: 16, top: 8 });
      List({ space: 16 }) {
        if (this.message) { ListItem() { Notice({ text: this.message }); } }
        if (this.downloadMessage) { ListItem() { Notice({ text: this.downloadMessage }); } }
        if (this.downloading) {
          ListItem() { Button('取消下载').onClick(() => this.downloader.cancel()).id('history-download-cancel'); }
        }
        if (this.kind === 'recordings') {
          // 记录可能被清理或补上关联录像，内容改变时更新卡片与点击回调。
          LazyForEach(this.recordingSource, (item: RecordingItem) => { ListItem() { this.recordingCard(item); } }, (item: RecordingItem) => JSON.stringify(item));
          if (this.recordings.length === 0 && !this.busy) { ListItem() { Notice({ text: '暂无已完成的录像' }); } }
          ListItem() { Text('显示最近 200 条录像；按天查找完整录像请进入对应通道。').fontSize(12).fontColor(Palette.secondary).width('100%'); }
        } else {
          LazyForEach(this.eventSource, (item: EventItem) => { ListItem() { this.eventCard(item); } }, (item: EventItem) => JSON.stringify(item));
          if (this.events.length === 0 && !this.busy) { ListItem() { Notice({ text: '暂无符合筛选条件的事件' }); } }
        }
        if (this.busy && this.events.length === 0 && this.recordings.length === 0) { ListItem() { LoadingProgress().width(32).height(32); } }
      }.lanes(this.kind === 'events' && this.contentWidth >= 840 ? 2 : 1, 16).cachedCount(2)
        .padding({ left: 16, right: 16 }).contentEndOffset(24 + this.bottomInset)
        .layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor(Palette.background)
      .onAreaChange((_old: Area, area: Area) => { this.contentWidth = Number(area.width); });
  }
}
