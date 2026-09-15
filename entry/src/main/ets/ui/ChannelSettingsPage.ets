import { RecorderState } from './RecorderState';
import { Palette, Notice } from './Theme';
import { RecorderApi } from '../data/RecorderApi';
import { mergeConfigChanges } from '../data/ConfigMerge';
import { ChannelConfig, RecorderConfig, ChannelPatch, RecordingPatch, DetectionPatch, PrivacyPatch } from '../model/Models';

@Observed
class ChannelDraft {
  faceMosaic: boolean = false; plateMosaic: boolean = false; privacySupported: boolean = false;
  name: string; enabled: boolean; width: string; height: string; fps: string; preview: string;
  recording: boolean; minutes: number; detecting: boolean; person: boolean; vehicle: boolean; animal: boolean;
  threshold: string; confidence: string; interval: string; tolerance: string; copyOthers: boolean = false;
  constructor(channel: ChannelConfig) {
    this.faceMosaic = channel.privacy?.face_mosaic ?? false; this.plateMosaic = channel.privacy?.plate_mosaic ?? false;
    this.privacySupported = channel.privacy !== undefined;
    this.name = channel.name; this.enabled = channel.enabled; this.width = channel.width.toString(); this.height = channel.height.toString();
    this.fps = channel.fps.toString(); this.preview = channel.preview_fps.toString(); this.recording = channel.recording.enabled;
    this.minutes = channel.recording.segment_minutes; this.detecting = channel.detection.enabled;
    this.person = channel.detection.categories.includes('person'); this.vehicle = channel.detection.categories.includes('vehicle');
    this.animal = channel.detection.categories.includes('animal'); this.threshold = channel.detection.threshold_seconds.toString();
    this.confidence = channel.detection.confidence.toString(); this.interval = channel.detection.sample_interval.toString();
    this.tolerance = channel.detection.lost_tolerance_seconds.toString();
  }
}
class ChannelSession {
  config: RecorderConfig; original: ChannelConfig; draft: ChannelDraft;
  constructor(config: RecorderConfig, channel: ChannelConfig) {
    this.config = config; this.original = channel; this.draft = new ChannelDraft(channel);
  }
}
const channelDrafts: Map<string, ChannelSession> = new Map<string, ChannelSession>();

function rebaseDraft(draft: ChannelDraft, original: ChannelConfig, updated: ChannelConfig): ChannelDraft {
  const before = new ChannelDraft(original); const after = new ChannelDraft(updated);
  // 保留未完成的文本输入，未修改字段使用另一客户端或批量应用后的最新值。
  if (draft.faceMosaic !== before.faceMosaic) after.faceMosaic = draft.faceMosaic;
  if (draft.plateMosaic !== before.plateMosaic) after.plateMosaic = draft.plateMosaic;
  if (draft.name !== before.name) after.name = draft.name;
  if (draft.enabled !== before.enabled) after.enabled = draft.enabled;
  if (draft.width !== before.width) after.width = draft.width;
  if (draft.height !== before.height) after.height = draft.height;
  if (draft.fps !== before.fps) after.fps = draft.fps;
  if (draft.preview !== before.preview) after.preview = draft.preview;
  if (draft.recording !== before.recording) after.recording = draft.recording;
  if (draft.minutes !== before.minutes) after.minutes = draft.minutes;
  if (draft.detecting !== before.detecting) after.detecting = draft.detecting;
  if (draft.person !== before.person) after.person = draft.person;
  if (draft.vehicle !== before.vehicle) after.vehicle = draft.vehicle;
  if (draft.animal !== before.animal) after.animal = draft.animal;
  if (draft.threshold !== before.threshold) after.threshold = draft.threshold;
  if (draft.confidence !== before.confidence) after.confidence = draft.confidence;
  if (draft.interval !== before.interval) after.interval = draft.interval;
  if (draft.tolerance !== before.tolerance) after.tolerance = draft.tolerance;
  after.copyOthers = draft.copyOthers; return after;
}

function requiredNumber(value: string, label: string): number {
  if (!value.trim() || !Number.isFinite(Number(value))) throw new Error('请填写有效的' + label);
  return Number(value);
}
function categories(draft: ChannelDraft): string[] {
  const values: string[] = [];
  if (draft.person) values.push('person'); if (draft.vehicle) values.push('vehicle'); if (draft.animal) values.push('animal');
  return values;
}
/** 差异补丁只携带用户编辑的字段，接线与扩展配置由数据层原样保留。 */
function changedPatch(id: number, draft: ChannelDraft, original: ChannelConfig): ChannelPatch {
  const patch: ChannelPatch = { id: id };
  const width = requiredNumber(draft.width, '宽度'); const height = requiredNumber(draft.height, '高度');
  const fps = requiredNumber(draft.fps, '录像帧率'); const preview = requiredNumber(draft.preview, '预览帧率');
  const threshold = requiredNumber(draft.threshold, '停留阈值'); const confidence = requiredNumber(draft.confidence, '置信度');
  const interval = requiredNumber(draft.interval, '侦测间隔'); const tolerance = requiredNumber(draft.tolerance, '消失容忍时间');
  if (draft.name.trim() !== original.name) patch.name = draft.name.trim();
  if (draft.enabled !== original.enabled) patch.enabled = draft.enabled;
  if (width !== original.width) patch.width = width; if (height !== original.height) patch.height = height;
  if (fps !== original.fps) patch.fps = fps; if (preview !== original.preview_fps) patch.preview_fps = preview;
  const privacy: PrivacyPatch = {};
  if (draft.faceMosaic !== (original.privacy?.face_mosaic ?? false)) privacy.face_mosaic = draft.faceMosaic;
  if (draft.plateMosaic !== (original.privacy?.plate_mosaic ?? false)) privacy.plate_mosaic = draft.plateMosaic;
  if (Object.keys(privacy).length > 0) patch.privacy = privacy;
  const recording: RecordingPatch = {};
  if (draft.recording !== original.recording.enabled) recording.enabled = draft.recording;
  if (draft.minutes !== original.recording.segment_minutes) recording.segment_minutes = draft.minutes;
  if (Object.keys(recording).length > 0) patch.recording = recording;
  const detection: DetectionPatch = {};
  if (draft.detecting !== original.detection.enabled) detection.enabled = draft.detecting;
  if (categories(draft).sort().join(',') !== original.detection.categories.slice().sort().join(',')) detection.categories = categories(draft);
  if (threshold !== original.detection.threshold_seconds) detection.threshold_seconds = threshold;
  if (confidence !== original.detection.confidence) detection.confidence = confidence;
  if (interval !== original.detection.sample_interval) detection.sample_interval = interval;
  if (tolerance !== original.detection.lost_tolerance_seconds) detection.lost_tolerance_seconds = tolerance;
  if (Object.keys(detection).length > 0) patch.detection = detection;
  return patch;
}
function copiedPatch(id: number, draft: ChannelDraft): ChannelPatch {
  return { id: id, width: requiredNumber(draft.width, '宽度'), height: requiredNumber(draft.height, '高度'),
    fps: requiredNumber(draft.fps, '录像帧率'), preview_fps: requiredNumber(draft.preview, '预览帧率'),
    privacy: draft.privacySupported ? { face_mosaic: draft.faceMosaic, plate_mosaic: draft.plateMosaic } : undefined,
    recording: { enabled: draft.recording, segment_minutes: draft.minutes },
    detection: { enabled: draft.detecting, categories: categories(draft), threshold_seconds: requiredNumber(draft.threshold, '停留阈值'),
      confidence: requiredNumber(draft.confidence, '置信度'), sample_interval: requiredNumber(draft.interval, '侦测间隔'),
      lost_tolerance_seconds: requiredNumber(draft.tolerance, '消失容忍时间') } };
}

@Component
export struct ChannelSettingsPage {
  @ObjectLink state: RecorderState;
  @Prop @Watch('channelChanged') channelId: number = 1;
  @State private draft?: ChannelDraft = undefined;
  @State private loading: boolean = false;
  @State private saving: boolean = false;
  @State private message: string = '';
  private request?: RecorderApi = undefined;
  private generation: number = 0;
  private mounted: boolean = false;
  private cancelPrivacy?: () => void = undefined;
  private readonly minutes: number[] = [1, 3, 5, 10];

  aboutToAppear(): void { this.mounted = true; this.saving = false; this.load(); }
  aboutToDisappear(): void { this.cancelPrivacy?.(); this.cancelPrivacy = undefined; this.mounted = false; this.generation++; this.request?.cancelAll(); }
  private channelChanged(): void { this.load(); }
  private draftKey(): string { return this.state.endpoint + '#' + this.channelId; }
  private pageIsCurrent(generation: number, key: string): boolean {
    return this.mounted && generation === this.generation && key === this.draftKey();
  }
  private async load(): Promise<void> {
    if (!this.mounted) return;
    const generation = ++this.generation; this.request?.cancelAll(); this.message = '';
    const key = this.draftKey(); const saved = channelDrafts.get(key);
    this.draft = saved?.draft; this.loading = true;
    const api = this.state.api(); this.request = api;
    try {
      const config = await api.getConfig();
      if (!this.pageIsCurrent(generation, key)) return;
      const channel = config.channels.find((item: ChannelConfig): boolean => item.id === this.channelId);
      if (!channel) throw new Error('录像机没有返回此通道的设置');
      const session = new ChannelSession(config, channel);
      if (saved) session.draft = rebaseDraft(saved.draft, saved.original, channel);
      channelDrafts.set(key, session); this.draft = session.draft;
    } catch (error) { if (this.pageIsCurrent(generation, key)) this.message = (error as Error).message; }
    finally { if (this.pageIsCurrent(generation, key)) this.loading = false; }
  }
  private otherNames(): string {
    return channelDrafts.get(this.draftKey())?.config.channels.filter((channel: ChannelConfig): boolean => channel.id !== this.channelId)
      .map((channel: ChannelConfig): string => channel.name).join('、') || '其他四路通道';
  }
  private chooseCopy(): void {
    if (!this.draft || this.saving || this.loading || !this.mounted) return;
    const generation = this.generation; const key = this.draftKey();
    this.getUIContext().showAlertDialog({
      title: '应用到其他通道',
      message: '目标：' + this.otherNames() + '。\n复制画质、录像、检测与马赛克设置。马赛克开启后会严重降低性能，并永久写入新录像。保留各路名称、通道开关和接线。点击“保存设置”后才会应用。',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: '加入待保存', action: (): void => {
        if (this.draft && this.pageIsCurrent(generation, key)) this.draft.copyOthers = true;
      } }
    });
  }
  private changePrivacy(face: boolean, enabled: boolean): void {
    const draft = this.draft; if (!draft || this.saving || this.loading || !draft.privacySupported) return;
    if (!enabled) { if (face) draft.faceMosaic = false; else draft.plateMosaic = false; return; }
    const generation = this.generation; const key = this.draftKey();
    // 原生 Toggle 会先切换视觉状态；取消时显式回写，避免显示已开但草稿未开的错位。
    if (face) draft.faceMosaic = true; else draft.plateMosaic = true;
    const rollback = (): void => { if (face) draft.faceMosaic = false; else draft.plateMosaic = false; this.cancelPrivacy = undefined; };
    this.cancelPrivacy = rollback;
    this.getUIContext().showAlertDialog({ title: '开启马赛克？',
      message: '开启后会严重降低性能，可能降低预览与录像帧率。马赛克会永久写入新录像，不能恢复原画面；已有录像不会改变。采用间隔检测与逐帧跟踪，快速新目标可能短暂漏遮挡。',
      cancel: rollback,
      primaryButton: { value: '取消', action: rollback },
      secondaryButton: { value: '仍然开启', action: (): void => {
        this.cancelPrivacy = undefined;
        if (this.pageIsCurrent(generation, key) && this.draft === draft) {
          if (face) draft.faceMosaic = true; else draft.plateMosaic = true;
        }
      } }
    });
  }
  private async save(): Promise<void> {
    const draft = this.draft; const key = this.draftKey(); const session = channelDrafts.get(key);
    if (!draft || !session || this.saving || this.loading || !this.mounted) return;
    const generation = this.generation;
    this.saving = true; this.message = '';
    try {
      const own = changedPatch(this.channelId, draft, session.original);
      const patches: ChannelPatch[] = Object.keys(own).length > 1 ? [own] : [];
      if (draft.copyOthers) {
        session.config.channels.forEach((channel: ChannelConfig): void => {
          if (channel.id !== this.channelId) patches.push(copiedPatch(channel.id, draft));
        });
      }
      if (patches.length === 0) { this.message = '没有需要保存的修改'; return; }
      mergeConfigChanges(session.config, { channels: patches });
      // 已发出的 PUT 可能已生效；离页只停止后续请求和旧页面回调，不承诺撤销。
      const api = this.state.api(); this.request?.cancelAll(); this.request = api;
      const result = await api.saveConfigChanges({ channels: patches });
      if (!this.pageIsCurrent(generation, key)) return;
      const updated = result.config.channels.find((channel: ChannelConfig): boolean => channel.id === this.channelId);
      if (!updated) throw new Error('保存后未找到此通道');
      if (draft.copyOthers) {
        result.config.channels.forEach((channel: ChannelConfig): void => {
          if (channel.id === this.channelId) return;
          const otherKey = this.state.endpoint + '#' + channel.id; const other = channelDrafts.get(otherKey);
          if (other) {
            const refreshed = new ChannelSession(result.config, channel);
            refreshed.draft = rebaseDraft(other.draft, other.original, channel); channelDrafts.set(otherKey, refreshed);
          }
        });
      }
      const saved = new ChannelSession(result.config, updated); channelDrafts.set(key, saved); this.draft = saved.draft;
      this.message = draft.copyOthers ? '本通道设置与批量应用已保存' : '通道设置已保存';
    } catch (error) { if (this.pageIsCurrent(generation, key)) this.message = (error as Error).message; }
    finally { if (this.pageIsCurrent(generation, key)) this.saving = false; }
  }
  @Builder private heading(text: string) {
    Text(text).fontSize(18).fontWeight(FontWeight.Medium).fontColor(Palette.text).width('100%').padding({ bottom: 4 });
  }
  @Builder private toggleRow(label: string, enabled: boolean, onChange: (value: boolean) => void, tag: string) {
    Row({ space: 12 }) {
      Text(label).fontSize(16).fontColor(Palette.text).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: enabled }).onChange(onChange).id(tag).accessibilityText(label).enabled(!this.saving);
    }.width('100%').constraintSize({ minHeight: 48 });
  }
  @Builder private numberField(label: string, value: string, onChange: (value: string) => void, tag: string) {
    Column({ space: 8 }) {
      Text(label).fontSize(15).fontColor(Palette.text).width('100%');
      TextInput({ text: value }).type(InputType.NUMBER_DECIMAL).onChange(onChange).id(tag).accessibilityText(label).enabled(!this.saving);
    }.width('100%');
  }
  @Builder private category(label: string, name: string, checked: boolean, onChange: (value: boolean) => void) {
    Row() {
      Checkbox({ name: name, group: 'detection-categories' }).select(checked).onChange(onChange)
        .id('detect-' + name).enabled(!this.saving).accessibilityText(label);
      Text(label).fontSize(16).fontColor(Palette.text);
    }.layoutWeight(1);
  }
  build() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.loading) { LoadingProgress().width(36).height(36).color(Palette.brand); }
        if (this.draft) {
          Column({ space: 14 }) {
            this.heading('通道');
            this.toggleRow('启用通道', this.draft.enabled, (value: boolean): void => { if (this.draft) this.draft.enabled = value; }, 'channel-enabled');
            TextInput({ text: this.draft.name, placeholder: '通道名称' }).maxLength(40).enabled(!this.saving)
              .onChange((value: string): void => { if (this.draft) this.draft.name = value; }).id('channel-name').accessibilityText('通道名称');
          }.padding(20).backgroundColor(Palette.card).borderRadius(24).width('100%');
          Column({ space: 16 }) {
            this.heading('画质');
            this.numberField('画面宽度（像素）', this.draft.width, (value: string): void => { if (this.draft) this.draft.width = value; }, 'channel-width');
            this.numberField('画面高度（像素）', this.draft.height, (value: string): void => { if (this.draft) this.draft.height = value; }, 'channel-height');
            this.numberField('录像帧率（1～30 帧/秒）', this.draft.fps, (value: string): void => { if (this.draft) this.draft.fps = value; }, 'channel-fps');
            this.numberField('预览帧率（不高于录像帧率）', this.draft.preview, (value: string): void => { if (this.draft) this.draft.preview = value; }, 'channel-preview-fps');
          }.padding(20).backgroundColor(Palette.card).borderRadius(24).width('100%');
          Column({ space: 14 }) {
            this.heading('连续录像');
            if (this.draft.privacySupported) {
              Row({ space: 12 }) {
                Text('开启车牌马赛克').fontSize(16).fontColor(Palette.text).layoutWeight(1);
                Toggle({ type: ToggleType.Switch, isOn: $$this.draft.plateMosaic }).enabled(!this.saving && !this.loading)
                  .onChange((v: boolean): void => this.changePrivacy(false, v)).id('privacy-plate');
              }.width('100%').constraintSize({ minHeight: 48 });
              Row({ space: 12 }) {
                Text('开启人脸马赛克').fontSize(16).fontColor(Palette.text).layoutWeight(1);
                Toggle({ type: ToggleType.Switch, isOn: $$this.draft.faceMosaic }).enabled(!this.saving && !this.loading)
                  .onChange((v: boolean): void => this.changePrivacy(true, v)).id('privacy-face');
              }.width('100%').constraintSize({ minHeight: 48 });
              Text('由主机处理，预览、事件截图和新录像均会遮挡。').fontSize(13).fontColor(Palette.secondary);
            } else { Text('请先升级录像机主机以支持马赛克。').fontSize(13).fontColor(Palette.secondary); }
            this.toggleRow('开启录像', this.draft.recording, (value: boolean): void => { if (this.draft) this.draft.recording = value; }, 'recording-enabled');
            Row() {
              Text('片段时长').fontColor(Palette.text).fontSize(16).layoutWeight(1);
              Select([{ value: '1 分钟' }, { value: '3 分钟' }, { value: '5 分钟' }, { value: '10 分钟' }])
                .selected(this.minutes.indexOf(this.draft.minutes)).value(this.draft.minutes + ' 分钟').enabled(!this.saving)
                .onSelect((index: number): void => { if (this.draft && this.minutes[index]) this.draft.minutes = this.minutes[index]; }).id('recording-minutes');
            }.width('100%');
          }.padding(20).backgroundColor(Palette.card).borderRadius(24).width('100%');
          Column({ space: 16 }) {
            this.heading('智能检测');
            this.toggleRow('开启检测', this.draft.detecting, (value: boolean): void => { if (this.draft) this.draft.detecting = value; }, 'detection-enabled');
            Row() {
              this.category('人', 'person', this.draft.person, (value: boolean): void => { if (this.draft) this.draft.person = value; });
              this.category('车', 'vehicle', this.draft.vehicle, (value: boolean): void => { if (this.draft) this.draft.vehicle = value; });
              this.category('动物', 'animal', this.draft.animal, (value: boolean): void => { if (this.draft) this.draft.animal = value; });
            }.width('100%');
            this.numberField('人 / 动物停留阈值（秒）', this.draft.threshold, (value: string): void => { if (this.draft) this.draft.threshold = value; }, 'detection-threshold');
            Text('人、车和动物确认出现时保存一次事件；仅人和动物达到阈值后再保存长时间停留事件。').fontSize(13).fontColor(Palette.secondary).width('100%');
            this.numberField('识别置信度（0.1～0.99）', this.draft.confidence, (value: string): void => { if (this.draft) this.draft.confidence = value; }, 'detection-confidence');
            this.numberField('侦测间隔（0.2～10 秒）', this.draft.interval, (value: string): void => { if (this.draft) this.draft.interval = value; }, 'detection-interval');
            this.numberField('消失容忍时间（不小于侦测间隔）', this.draft.tolerance, (value: string): void => { if (this.draft) this.draft.tolerance = value; }, 'detection-tolerance');
          }.padding(20).backgroundColor(Palette.card).borderRadius(24).width('100%');
          Column({ space: 12 }) {
            if (this.draft.copyOthers) {
              Text('待应用：' + this.otherNames()).fontSize(14).fontColor(Palette.secondary).width('100%');
              Button('取消批量应用').backgroundColor(Palette.card).fontColor(Palette.brand).enabled(!this.saving)
                .onClick(() => { if (this.draft) this.draft.copyOthers = false; }).id('channel-copy-cancel');
            } else {
              Button('应用到其他通道').width('100%').height(48).backgroundColor(Palette.card).fontColor(Palette.brand)
                .enabled(!this.saving && !this.loading).onClick(() => this.chooseCopy()).id('channel-copy');
            }
            Button(this.saving ? '正在保存…' : '保存设置').width('100%').height(48).backgroundColor(Palette.brand)
              .enabled(!this.saving && !this.loading).onClick(() => this.save()).id('channel-save');
          }.width('100%');
        }
        Notice({ text: this.message });
        if (!this.draft && !this.loading) { Button('重试').onClick(() => this.load()).id('channel-settings-retry'); }
      }.padding(16).width('100%').constraintSize({ maxWidth: 840 });
    }.width('100%').height('100%').backgroundColor(Palette.background).scrollBar(BarState.Off).align(Alignment.Top);
  }
}
