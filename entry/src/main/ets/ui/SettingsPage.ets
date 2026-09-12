import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { RecorderState } from './RecorderState';
import { Palette, Notice, bytesText } from './Theme';
import { RecorderApi, normalizeEndpoint } from '../data/RecorderApi';
import { PreferencesService } from '../data/PreferencesService';
import { mergeConfigChanges } from '../data/ConfigMerge';
import { objects, textValue, numberValue } from '../data/JsonCodec';
import { NativeDownloader } from '../media/NativeDownloader';
import { AppearanceMode, RecorderConfig, StorageTargets, StorageTarget, StoragePatch, ModelInfo, JsonObject } from '../model/Models';

@Observed
class StorageDraft {
  target: string; maximum: string; reserve: string;
  constructor(config: RecorderConfig) {
    this.target = config.storage.target_id; this.maximum = config.storage.max_gb.toString();
    this.reserve = config.storage.min_free_gb.toString();
  }
}
class StorageSession {
  config: RecorderConfig; draft: StorageDraft;
  constructor(config: RecorderConfig) { this.config = config; this.draft = new StorageDraft(config); }
}
// 分类返回与旋转时保留当前设备的未保存输入，不串到另一台设备。
const storageDrafts: Map<string, StorageSession> = new Map<string, StorageSession>();

@Component
export struct SettingsPage {
  @ObjectLink state: RecorderState;
  @Prop @Watch('categoryChanged') category: string = 'home';
  @Prop bottomInset: number = 0;
  onOpen: (category: string) => void = () => {};
  onEndpointChanged: (endpoint: string) => void = () => {};
  @State private endpointDraft: string = '';
  @State private message: string = '';
  @State private loading: boolean = false;
  @State private busy: boolean = false;
  @State private storage?: StorageDraft = undefined;
  @State private targets: StorageTargets = { selected_id: '', targets: [] };
  @State private model?: ModelInfo = undefined;
  @State private logs: JsonObject[] = [];
  @State private downloaded: number = 0;
  private request?: RecorderApi = undefined;
  private generation: number = 0;
  private mounted: boolean = false;
  private downloader: NativeDownloader = new NativeDownloader();
  private appearanceTimer: number = -1;

  aboutToAppear(): void { this.mounted = true; this.busy = false; this.endpointDraft = this.state.endpoint; this.load(); }
  aboutToDisappear(): void {
    this.mounted = false; this.generation++; this.cancelAppearance(); this.request?.cancelAll(); this.downloader.cancel();
  }
  private categoryChanged(): void { this.load(); }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private pageIsCurrent(generation: number, endpoint: string, category: string): boolean {
    return this.mounted && generation === this.generation && endpoint === this.state.endpoint && category === this.category;
  }
  private async load(): Promise<void> {
    if (!this.mounted) return;
    this.cancelAppearance();
    const generation = ++this.generation; this.request?.cancelAll(); this.message = '';
    const category = this.category;
    if (!['storage', 'model', 'logs'].includes(category)) { this.loading = false; return; }
    const endpoint = this.state.endpoint; const api = new RecorderApi(endpoint); this.request = api; this.loading = true;
    try {
      if (category === 'storage') {
        const oldSession = storageDrafts.get(endpoint);
        const session = new StorageSession(await api.getConfig());
        const targets = await api.getStorageTargets();
        if (!this.pageIsCurrent(generation, endpoint, category)) return;
        if (oldSession) {
          // 刷新后接纳外部最新设置，同时保留本页真正编辑过的输入。
          if (oldSession.draft.target !== oldSession.config.storage.target_id) session.draft.target = oldSession.draft.target;
          if (oldSession.draft.maximum !== oldSession.config.storage.max_gb.toString()) session.draft.maximum = oldSession.draft.maximum;
          if (oldSession.draft.reserve !== oldSession.config.storage.min_free_gb.toString()) session.draft.reserve = oldSession.draft.reserve;
        }
        storageDrafts.set(endpoint, session); this.storage = session.draft; this.targets = targets;
      } else if (category === 'model') {
        const model = await api.getModel(); if (this.pageIsCurrent(generation, endpoint, category)) this.model = model;
      } else {
        const logs = await api.getLogs(); if (this.pageIsCurrent(generation, endpoint, category)) this.logs = objects(logs['items']);
      }
    } catch (error) { if (this.pageIsCurrent(generation, endpoint, category)) this.message = (error as Error).message; }
    finally { if (this.pageIsCurrent(generation, endpoint, category)) this.loading = false; }
  }
  private async saveEndpoint(): Promise<void> {
    if (this.busy || !this.mounted) return;
    const generation = this.generation; const oldEndpoint = this.state.endpoint; const category = this.category;
    this.busy = true;
    try {
      const endpoint = normalizeEndpoint(this.endpointDraft);
      await PreferencesService.saveEndpoint(this.context(), endpoint);
      if (!this.pageIsCurrent(generation, oldEndpoint, category)) return;
      this.endpointDraft = endpoint; this.message = '连接地址已保存'; this.onEndpointChanged(endpoint);
    } catch (error) { if (this.pageIsCurrent(generation, oldEndpoint, category)) this.message = (error as Error).message; }
    finally { if (this.pageIsCurrent(generation, oldEndpoint, category)) this.busy = false; }
  }
  private cancelAppearance(): void {
    if (this.appearanceTimer >= 0) clearTimeout(this.appearanceTimer);
    this.appearanceTimer = -1;
  }
  private requestAppearance(mode: AppearanceMode): void {
    if (!this.mounted || this.category !== 'appearance' || this.busy ||
      mode === this.state.appearance || this.appearanceTimer >= 0) return;
    const generation = this.generation; const endpoint = this.state.endpoint; const category = this.category;
    // Radio 重建也会回调；当前值不保存，新选择统一延后，避免渲染时改状态。
    this.appearanceTimer = setTimeout((): void => {
      this.appearanceTimer = -1;
      if (this.pageIsCurrent(generation, endpoint, category)) this.saveAppearance(mode, generation, endpoint, category);
    }, 0);
  }
  private async saveAppearance(mode: AppearanceMode, generation: number, endpoint: string, category: string): Promise<void> {
    if (!this.pageIsCurrent(generation, endpoint, category) || category !== 'appearance' ||
      this.busy || mode === this.state.appearance) return;
    this.busy = true;
    try {
      await PreferencesService.saveAppearance(this.context(), mode);
      if (!this.pageIsCurrent(generation, endpoint, category)) return;
      this.context().getApplicationContext().setColorMode(mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
        mode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      this.state.appearance = mode; this.message = '';
    } catch (error) { if (this.pageIsCurrent(generation, endpoint, category)) this.message = (error as Error).message; }
    finally { if (this.pageIsCurrent(generation, endpoint, category)) this.busy = false; }
  }
  private async saveStorage(): Promise<void> {
    const draft = this.storage; const endpoint = this.state.endpoint; const session = storageDrafts.get(endpoint);
    if (!draft || !session || this.busy || this.loading || !this.mounted) return;
    const generation = this.generation; const category = this.category;
    this.busy = true; this.message = '';
    try {
      if (!draft.maximum.trim() || !draft.reserve.trim()) throw new Error('请填写录像空间上限与保留空间');
      const patch: StoragePatch = {};
      if (draft.target !== session.config.storage.target_id) patch.target_id = draft.target;
      if (Number(draft.maximum) !== session.config.storage.max_gb) patch.max_gb = Number(draft.maximum);
      if (Number(draft.reserve) !== session.config.storage.min_free_gb) patch.min_free_gb = Number(draft.reserve);
      if (Object.keys(patch).length === 0) { this.message = '没有需要保存的修改'; return; }
      mergeConfigChanges(session.config, { storage: patch });
      // 离页时取消同一实例，数据层会在读取最新配置后再次核验取消令牌。
      const api = this.state.api(); this.request?.cancelAll(); this.request = api;
      const result = await api.saveConfigChanges({ storage: patch });
      if (!this.pageIsCurrent(generation, endpoint, category)) return;
      const saved = new StorageSession(result.config); storageDrafts.set(endpoint, saved); this.storage = saved.draft;
      this.message = result.restart_required ? '保存成功，监听地址的变更需要重启板端服务后生效' : '录像存储设置已保存';
    } catch (error) { if (this.pageIsCurrent(generation, endpoint, category)) this.message = (error as Error).message; }
    finally { if (this.pageIsCurrent(generation, endpoint, category)) this.busy = false; }
  }
  private async downloadLogs(): Promise<void> {
    if (this.busy || !this.mounted) return;
    const generation = this.generation; const endpoint = this.state.endpoint; const category = this.category;
    this.busy = true; this.downloaded = 0; this.message = '正在准备诊断日志…';
    try {
      const result = await this.downloader.save(this.context(), this.state.api().mediaUrl('/api/logs/download'),
        'logs', `smart-recorder-logs-${Date.now()}.zip`, (bytes: number): void => {
          if (this.pageIsCurrent(generation, endpoint, category)) this.downloaded = bytes;
        });
      if (!this.pageIsCurrent(generation, endpoint, category)) return;
      this.message = result.saved ? `日志已保存 · ${bytesText(result.bytes)}` : '已取消保存';
    } catch (error) { if (this.pageIsCurrent(generation, endpoint, category)) this.message = (error as Error).message; }
    finally { if (this.pageIsCurrent(generation, endpoint, category)) this.busy = false; }
  }
  private targetOptions(): SelectOption[] {
    return this.targets.targets.map((target: StorageTarget): SelectOption => ({
      value: `${target.label || target.id}${target.available && target.writable ? '' : '（不可用）'}`
    }));
  }
  private targetIndex(): number { return this.targets.targets.findIndex((target: StorageTarget): boolean => target.id === this.storage?.target); }
  private targetDescription(): string {
    const target = this.targets.targets.find((item: StorageTarget): boolean => item.id === this.storage?.target);
    return target ? `${bytesText(target.free_bytes)} 可用 / ${bytesText(target.total_bytes)}${target.error ? '\n' + target.error : ''}` : '当前介质未连接';
  }
  @Builder private categoryRow(title: string, subtitle: string, category: string) {
    ListItem() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text(title).fontSize(17).fontColor(Palette.text);
            Text(subtitle).fontSize(13).fontColor(Palette.secondary).maxLines(2);
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          Text('›').fontSize(26).fontColor(Palette.secondary);
        }.width('100%').padding(20);
      }.width('100%').backgroundColor(Palette.card).borderRadius(20).onClick(() => this.onOpen(category))
        .id(`settings-category-${category}`).accessibilityText(`${title}，${subtitle}`);
    }
  }
  @Builder private info(label: string, value: string) {
    Column({ space: 6 }) {
      Text(label).fontSize(13).fontColor(Palette.secondary);
      Text(value || '—').fontSize(16).fontColor(Palette.text).width('100%');
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 10, bottom: 10 });
  }
  @Builder private appearanceRow(label: string, mode: AppearanceMode) {
    Row({ space: 12 }) {
      Text(label).fontSize(17).fontColor(Palette.text).layoutWeight(1);
      Radio({ value: mode, group: 'recorder-appearance' }).checked(this.state.appearance === mode)
        .onChange((checked: boolean): void => { if (checked) this.requestAppearance(mode); }).enabled(!this.busy)
        .id(`appearance-${mode}`).accessibilityText(label);
    }.width('100%').padding({ top: 10, bottom: 10 }).onClick(() => this.requestAppearance(mode));
  }
  build() {
    if (this.category === 'home') {
      List({ space: 12 }) {
        this.categoryRow('设备连接', this.state.endpoint.replace('http://', '').replace('https://', ''), 'connection');
        this.categoryRow('录像存储', '保存介质与循环录像空间', 'storage');
        this.categoryRow('识别模型', '模型版本与硬件状态', 'model');
        this.categoryRow('诊断日志', '查看和下载日志', 'logs');
        this.categoryRow('外观与显示', this.state.appearance === 'dark' ? '深色' : this.state.appearance === 'system' ? '跟随系统' : '浅色', 'appearance');
      }.padding({ left: 16, right: 16, top: 16 }).contentEndOffset(16 + this.bottomInset)
        .width('100%').height('100%').backgroundColor(Palette.background).scrollBar(BarState.Off);
    } else {
      Scroll() {
        Column({ space: 16 }) {
          if (this.category === 'connection') {
            Column({ space: 14 }) {
              this.info('录像机地址', '手机或平板与录像机连接同一局域网');
              TextInput({ text: this.endpointDraft, placeholder: '192.168.10.172:8080' }).fontSize(16).fontColor(Palette.text).enabled(!this.busy)
                .onChange((value: string): void => { this.endpointDraft = value; }).id('endpoint-input');
              Button('保存并连接').width('100%').height(48).backgroundColor(Palette.brand).enabled(!this.busy)
                .onClick(() => this.saveEndpoint()).id('endpoint-save');
            }.padding(20).backgroundColor(Palette.card).borderRadius(24).width('100%');
          } else if (this.category === 'appearance') {
            Column() {
              this.appearanceRow('浅色', 'light'); Divider().color(Palette.line);
              this.appearanceRow('深色', 'dark'); Divider().color(Palette.line);
              this.appearanceRow('跟随系统', 'system');
            }.padding(20).width('100%').backgroundColor(Palette.card).borderRadius(24);
          } else if (this.category === 'storage' && this.storage) {
            Column({ space: 14 }) {
              Text('录像保存介质').fontColor(Palette.text).fontSize(17).width('100%');
              Select(this.targetOptions()).selected(this.targetIndex()).value(this.targetOptions()[this.targetIndex()]?.value || '请选择保存介质').enabled(!this.busy)
                .onSelect((index: number): void => { if (this.storage && this.targets.targets[index]) this.storage.target = this.targets.targets[index].id; })
                .width('100%').id('storage-target');
              Text(this.targetDescription()).fontSize(13).fontColor(Palette.secondary).width('100%');
              Text('录像空间上限（GB）').fontSize(15).fontColor(Palette.text).width('100%');
              TextInput({ text: this.storage.maximum }).type(InputType.NUMBER_DECIMAL).enabled(!this.busy).onChange((value: string): void => { if (this.storage) this.storage.maximum = value; }).id('storage-maximum');
              Text('保留可用空间（GB）').fontSize(15).fontColor(Palette.text).width('100%');
              TextInput({ text: this.storage.reserve }).type(InputType.NUMBER_DECIMAL).enabled(!this.busy).onChange((value: string): void => { if (this.storage) this.storage.reserve = value; }).id('storage-reserve');
              Text('空间不足时按时间清理本程序已完成的旧录像和事件。外置介质需先在录像机系统中挂载。').fontSize(13).fontColor(Palette.secondary);
              Button('保存存储设置').width('100%').height(48).backgroundColor(Palette.brand).enabled(!this.busy && !this.loading).onClick(() => this.saveStorage()).id('storage-save');
            }.padding(20).backgroundColor(Palette.card).borderRadius(24).width('100%');
          } else if (this.category === 'model' && this.model) {
            Column() {
              this.info('识别模型', this.model.name); Divider().color(Palette.line);
              this.info('版本', this.model.version); Divider().color(Palette.line);
              this.info('目标跟踪', this.model.tracker); Divider().color(Palette.line);
              this.info('推理后端', this.model.backend_label); Divider().color(Palette.line);
              this.info('SDK', this.model.sdk_version); Divider().color(Palette.line);
              this.info('NPU', this.model.npu.used ? '正在使用' : '当前未使用'); Divider().color(Palette.line);
              this.info('VPU', this.model.vpu.used ? '正在使用' : '当前未使用');
              ForEach(this.model.limitations, (text: string): void => { this.info('识别范围', text); });
              if (this.model.error) { Notice({ text: this.model.error }); }
            }.padding(20).backgroundColor(Palette.card).borderRadius(24).width('100%');
          } else if (this.category === 'logs') {
            Column({ space: 12 }) {
              ForEach(this.logs, (item: JsonObject): void => {
                this.info(textValue(item['name'], '日志'), bytesText(numberValue(item['size_bytes'])));
              });
              if (this.logs.length === 0 && !this.loading) { Text('当前没有可列出的日志').fontColor(Palette.secondary).fontSize(15); }
              Text('诊断包包含日志尾部、脱敏配置、运行状态与版本信息。').fontSize(14).fontColor(Palette.secondary).width('100%');
              Button(this.busy ? `正在下载 · ${bytesText(this.downloaded)}` : '下载诊断日志').width('100%').height(48)
                .backgroundColor(Palette.brand).enabled(!this.busy).onClick(() => this.downloadLogs()).id('logs-download');
            }.padding(20).backgroundColor(Palette.card).borderRadius(24).width('100%');
          }
          if (this.loading) { LoadingProgress().width(36).height(36).color(Palette.brand); }
          Notice({ text: this.message });
          if (['storage', 'model', 'logs'].includes(this.category)) {
            Button('刷新').backgroundColor(Palette.card).fontColor(Palette.brand).enabled(!this.busy && !this.loading).onClick(() => this.load()).id('settings-refresh');
          }
        }.padding(16).width('100%').constraintSize({ maxWidth: 840 });
      }.width('100%').height('100%').backgroundColor(Palette.background).scrollBar(BarState.Off).align(Alignment.Top);
    }
  }
}
