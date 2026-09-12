import { TimelineTick, timelineTicks, TimeRange,
  recordingRanges, timestamp, TimelineEvent, clockText } from '../model/Timeline';
import { Palette, eventColor } from './Theme';
import { TimelineState } from './TimelineState';

const EVENT_LANES: string[] = ['dwell', 'person', 'vehicle', 'animal'];
interface ColoredRange { start: number; end: number; type: string; }

/** Scroll 只移动时间标尺；色带在可见画布绘制，不为全天万条索引创建万级节点。 */
@Component
export struct DayTimeline {
  @ObjectLink @Watch('dataChanged') data: TimelineState;
  @Prop @Watch('cursorChanged') selectedAt: number = 0;
  @Prop @Watch('activityChanged') active: boolean = true;
  @Prop @Watch('dataChanged') hourHeight: number = 240;
  onCursor: (at: number) => void = (_: number): void => {};
  onSelect: (at: number) => void = (_: number): void => {};
  onScrubbing: (value: boolean) => void = (_: boolean): void => {};
  @State private viewport: number = 300;
  @State private ticks: TimelineTick[] = [];
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private scroller: Scroller = new Scroller();
  private ranges: TimeRange[] = [];
  private events: ColoredRange[] = [];
  private offsetY: number = 0;
  private canvasWidth: number = 300;
  private areaWidth: number = 0;
  private ready: boolean = false;
  private mounted: boolean = false;
  private scrubbing: boolean = false;
  private programmatic: boolean = false;
  private timer: number = -1;
  private alignmentTimer: number = -1;

  aboutToAppear(): void { this.mounted = true; this.dataChanged(); }
  aboutToDisappear(): void { this.mounted = false; this.cancel(); if (this.alignmentTimer >= 0) clearTimeout(this.alignmentTimer); }
  private cancel(): void {
    if (this.timer >= 0) clearTimeout(this.timer); this.timer = -1;
    if (this.scrubbing) { this.scrubbing = false; this.onScrubbing(false); }
  }
  private activityChanged(): void { if (!this.active) this.cancel(); }
  private dataChanged(): void {
    this.cancel(); this.ticks = timelineTicks(this.data.window, this.hourHeight >= 1200 ? 300000 : 3600000);
    this.ranges = recordingRanges(this.data);
    this.events = this.data.event_segments.map((event: TimelineEvent): ColoredRange =>
      ({ start: timestamp(event.start), end: timestamp(event.end), type: event.event_type }));
    this.cursorChanged(); this.draw();
  }
  private y(at: number): number { return (at - this.data.window.startMs) / 3600000 * this.hourHeight; }
  private axisHeight(): number { return this.y(this.data.window.endMs); }
  private cursorTime(): number {
    return Math.min(this.data.window.endMs, Math.max(this.data.window.startMs,
      this.data.window.startMs + this.offsetY / this.hourHeight * 3600000));
  }
  private cursorChanged(): void {
    if (!this.mounted || this.scrubbing) return;
    if (this.alignmentTimer >= 0) clearTimeout(this.alignmentTimer);
    // 等待当前布局提交后再对齐；程序滚动不能触发新的播放请求。
    this.alignmentTimer = setTimeout((): void => {
      this.alignmentTimer = -1;
      if (!this.mounted || this.scrubbing) return;
      this.programmatic = true;
      this.offsetY = Math.max(0, Math.min(this.axisHeight(), this.y(this.selectedAt)));
      this.scroller.scrollTo({ xOffset: 0, yOffset: this.offsetY, animation: false });
      this.draw(); this.programmatic = false;
    }, 0);
  }
  private startScroll(): void {
    if (!this.active || this.programmatic) return;
    if (this.timer >= 0) clearTimeout(this.timer); this.timer = -1;
    if (!this.scrubbing) { this.scrubbing = true; this.onScrubbing(true); }
  }
  private didScroll(): void {
    const offset = this.scroller.currentOffset();
    if (offset) this.offsetY = Math.max(0, Math.min(this.axisHeight(), offset.yOffset));
    this.draw();
    if (this.scrubbing && !this.programmatic) this.onCursor(this.cursorTime());
  }
  private stopScroll(): void {
    if (!this.scrubbing || !this.active) return;
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = setTimeout((): void => {
      this.timer = -1;
      if (!this.mounted || !this.active || !this.scrubbing) return;
      const at = this.cursorTime(); this.scrubbing = false; this.onScrubbing(false); this.onSelect(at);
    }, 180);
  }
  private paintRange(start: number, end: number, x: number, width: number, color: string): void {
    const top = this.viewport / 2 + this.y(start) - this.offsetY;
    const bottom = this.viewport / 2 + this.y(end) - this.offsetY;
    if (bottom < 0 || top > this.viewport) return;
    this.canvas.fillStyle = color;
    this.canvas.fillRect(x, Math.max(0, top), width, Math.max(1.5, Math.min(this.viewport, bottom) - Math.max(0, top)));
  }
  private draw(): void {
    if (!this.ready || !this.mounted) return;
    this.canvas.clearRect(0, 0, this.canvasWidth, this.viewport);
    const lane = Math.max(115, this.canvasWidth * 0.40);
    this.paintRange(this.data.window.startMs, this.data.window.endMs, lane, 10, '#9AA3AF');
    this.ranges.forEach((range: TimeRange): void => this.paintRange(range.start, range.end, lane, 10, '#4E92F7'));
    this.events.forEach((event: ColoredRange): void => {
      this.paintRange(event.start, event.end, lane + 20 + EVENT_LANES.indexOf(event.type) * 13,
        8, eventColor(event.type));
    });
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.scroller) {
        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.ticks, (tick: TimelineTick): void => {
            Row({ space: 8 }) {
              Text(tick.label).fontSize(12).fontColor(Palette.secondary).width(108);
              Row().height(0.5).width(16).backgroundColor(Palette.line);
            }.position({ x: 12, y: this.viewport / 2 + this.y(tick.at) - 8 });
          }, (tick: TimelineTick): string => `${tick.at}`);
        }.width('100%').height(this.axisHeight() + this.viewport);
      }.width('100%').height('100%').scrollable(ScrollDirection.Vertical).scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None).enabled(this.active).id('channel-day-timeline')
        .onWillScroll((_x: number, _y: number, _state: ScrollState, source: ScrollSource): void => {
          if (source !== ScrollSource.SCROLLER && source !== ScrollSource.SCROLLER_ANIMATION) this.startScroll();
        })
        .onDidScroll((): void => this.didScroll()).onScrollStop((): void => this.stopScroll());
      Canvas(this.canvas).width('100%').height('100%').hitTestBehavior(HitTestMode.None)
        .onReady((): void => { this.ready = true; this.draw(); })
        .onAreaChange((_, area: Area): void => { this.canvasWidth = Number(area.width); this.draw(); });
      Row({ space: 8 }) {
        Text(clockText(this.selectedAt, this.data.window)).fontSize(14).fontColor(Palette.brand)
          .backgroundColor(Palette.card).padding({ left: 8, right: 8, top: 4, bottom: 4 }).borderRadius(8);
        Row().height(1).layoutWeight(1).backgroundColor(Palette.brand);
      }.width('100%').position({ x: 0, y: this.viewport / 2 - 13 }).hitTestBehavior(HitTestMode.None);
    }.width('100%').height('100%').backgroundColor(Palette.card).borderRadius(16).clip(true)
      .onAreaChange((_, area: Area): void => {
        if (this.viewport !== Number(area.height) || this.areaWidth !== Number(area.width)) this.cancel();
        this.areaWidth = Number(area.width);
        this.viewport = Number(area.height); this.cursorChanged(); this.draw();
      });
  }
}
