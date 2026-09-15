import { JsonObject, RecorderStatus, ChannelStatus, RecordingItem, EventItem, ModelInfo, StorageTargets,
  StorageTarget, RecorderConfig, ChannelConfig, Detection } from '../model/Models';

export function objectValue(value: Object | undefined): JsonObject {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) return {};
  return value as JsonObject;
}
export function objects(value: Object | undefined): JsonObject[] {
  if (!Array.isArray(value)) return [];
  return (value as Object[]).map((item: Object): JsonObject => objectValue(item));
}
export function textValue(value: Object | undefined, fallback: string = ''): string {
  return typeof value === 'string' ? value as string : fallback;
}
export function numberValue(value: Object | undefined, fallback: number = NaN): number {
  return typeof value === 'number' && Number.isFinite(value as number) ? value as number : fallback;
}
export function boolValue(value: Object | undefined, fallback: boolean = false): boolean {
  return typeof value === 'boolean' ? value as boolean : fallback;
}
export function strings(value: Object | undefined): string[] {
  if (!Array.isArray(value)) return [];
  return (value as Object[]).filter((item: Object): boolean => typeof item === 'string').map((item: Object): string => item as string);
}
function numbers(value: Object | undefined): number[] {
  if (!Array.isArray(value)) return [];
  return (value as Object[]).map((item: Object): number => numberValue(item));
}
export function parseObject(text: string): JsonObject {
  const parsed = JSON.parse(text) as Object;
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('接口没有返回 JSON 对象');
  return parsed as JsonObject;
}
function requireFields(raw: JsonObject, text: string[], numbers: string[], booleans: string[], label: string): void {
  if (text.some((key: string): boolean => typeof raw[key] !== 'string' || textValue(raw[key]).trim().length === 0) ||
    numbers.some((key: string): boolean => !Number.isFinite(numberValue(raw[key]))) ||
    booleans.some((key: string): boolean => typeof raw[key] !== 'boolean')) {
    throw new Error(`${label}缺失或格式无效，请重新加载`);
  }
}
function validateRecord(raw: JsonObject, seen: Set<string>, label: string): void {
  requireFields(raw, ['id', 'created_at'], ['channel_id'], [], label);
  const id = textValue(raw['id']); const channel = numberValue(raw['channel_id']);
  if (seen.has(id) || !Number.isInteger(channel) || channel < 1 || channel > 5 ||
    !Number.isFinite(new Date(textValue(raw['created_at'])).getTime())) throw new Error(`${label}编号或时间无效`);
  seen.add(id);
}
export function parseStatus(raw: JsonObject): RecorderStatus {
  if (!Array.isArray(raw['channels'])) throw new Error('运行状态缺少通道列表');
  const system = objectValue(raw['system']); const memory = objectValue(system['memory']);
  const storage = objectValue(raw['storage']); const detector = objectValue(raw['detector']);
  const channels = objects(raw['channels']).map((c: JsonObject): ChannelStatus => {
    const detections = objects(c['detections']).map((d: JsonObject): Detection => ({ category: textValue(d['category']),
      bbox: numbers(d['bbox']), dwell_seconds: numberValue(d['dwell_seconds']), dwell_reached: boolValue(d['dwell_reached']) }));
    return { id: numberValue(c['id']), name: textValue(c['name']), enabled: boolValue(c['enabled'], true),
      state: textValue(c['state'], 'no_signal'), recording: boolValue(c['recording']), preview_fps: numberValue(c['preview_fps']),
      recording_fps: numberValue(c['recording_fps']), capture_fps: numberValue(c['capture_fps']), detections: detections,
      error: textValue(c['error']) };
  });
  const ids = new Set<number>();
  channels.forEach((c: ChannelStatus): void => {
    if (!Number.isInteger(c.id) || c.id < 1 || c.id > 5 || ids.has(c.id)) throw new Error('通道编号无效'); ids.add(c.id);
  });
  return { channels: channels, system: { hostname: textValue(system['hostname']), cpu_percent: numberValue(system['cpu_percent']),
    temperature_c: numberValue(system['temperature_c']), memory: { used_bytes: numberValue(memory['used_bytes']),
      total_bytes: numberValue(memory['total_bytes']), available_bytes: numberValue(memory['available_bytes']), used_percent: numberValue(memory['used_percent']) } },
    storage: { target_id: textValue(storage['target_id']), label: textValue(storage['label']), free_bytes: numberValue(storage['free_bytes']),
      total_bytes: numberValue(storage['total_bytes']), used_bytes: numberValue(storage['used_bytes']), error: textValue(storage['error']) },
    detector: { ready: boolValue(detector['ready']), model: textValue(detector['model']), backend: textValue(detector['backend']), error: textValue(detector['error']) },
    uptime_seconds: numberValue(raw['uptime_seconds']) };
}
export function parseRecordings(raw: JsonObject): RecordingItem[] {
  if (!Array.isArray(raw['items'])) throw new Error('录像列表格式无效');
  const seen = new Set<string>();
  objects(raw['items']).forEach((r: JsonObject): void => {
    validateRecord(r, seen, '录像信息');
    requireFields(r, ['url'], ['duration_seconds', 'size_bytes'], ['available'], '录像信息');
    if (numberValue(r['duration_seconds']) < 0 || numberValue(r['size_bytes']) < 0) throw new Error('录像时长或大小无效');
  });
  return objects(raw['items']).map((r: JsonObject): RecordingItem => ({ id: textValue(r['id']), channel_id: numberValue(r['channel_id']),
    created_at: textValue(r['created_at']), duration_seconds: numberValue(r['duration_seconds']), size_bytes: numberValue(r['size_bytes']),
    url: textValue(r['url']), available: boolValue(r['available']), error: textValue(r['error']) }));
}
export function parseEvents(raw: JsonObject): EventItem[] {
  if (!Array.isArray(raw['items'])) throw new Error('事件列表格式无效');
  const seen = new Set<string>();
  objects(raw['items']).forEach((r: JsonObject): void => {
    validateRecord(r, seen, '事件信息');
    requireFields(r, ['category', 'snapshot_url'], ['dwell_seconds'], [], '事件信息');
    if (!['person', 'vehicle', 'animal'].includes(textValue(r['category'])) ||
      !['person', 'vehicle', 'animal', 'dwell'].includes(textValue(r['event_type'], 'dwell')) ||
      numberValue(r['dwell_seconds']) < 0) throw new Error('事件类别或停留时间无效');
  });
  return objects(raw['items']).map((r: JsonObject): EventItem => ({ id: textValue(r['id']), channel_id: numberValue(r['channel_id']),
    created_at: textValue(r['created_at']), event_type: textValue(r['event_type'], 'dwell'), category: textValue(r['category']),
    label: textValue(r['label']), dwell_seconds: numberValue(r['dwell_seconds']), snapshot_url: textValue(r['snapshot_url']),
    recording_url: textValue(r['recording_url']), recording_available: boolValue(r['recording_available']), available: boolValue(r['available'], true) }));
}
export function parseModel(raw: JsonObject): ModelInfo {
  requireFields(raw, ['name', 'version', 'tracker', 'backend_label'], [], [], '识别模型信息');
  requireFields(objectValue(raw['npu']), [], [], ['used'], 'NPU 状态');
  requireFields(objectValue(raw['vpu']), [], [], ['used'], 'VPU 状态');
  return { name: textValue(raw['name']), version: textValue(raw['version']), tracker: textValue(raw['tracker']),
    backend_label: textValue(raw['backend_label']), sdk_version: textValue(raw['sdk_version']), limitations: strings(raw['limitations']),
    npu: { used: boolValue(objectValue(raw['npu'])['used']) }, vpu: { used: boolValue(objectValue(raw['vpu'])['used']) }, error: textValue(raw['error']) };
}
export function parseTargets(raw: JsonObject): StorageTargets {
  if (!Array.isArray(raw['targets'])) throw new Error('保存介质列表格式无效');
  const seen = new Set<string>();
  objects(raw['targets']).forEach((r: JsonObject): void => {
    requireFields(r, ['id'], [], ['available', 'writable'], '保存介质信息');
    const id = textValue(r['id']); if (seen.has(id)) throw new Error('保存介质编号重复'); seen.add(id);
  });
  return { selected_id: textValue(raw['selected_id']), targets: objects(raw['targets']).map((r: JsonObject): StorageTarget => ({
    id: textValue(r['id']), label: textValue(r['label']), available: boolValue(r['available']), writable: boolValue(r['writable']),
    free_bytes: numberValue(r['free_bytes']), total_bytes: numberValue(r['total_bytes']), error: textValue(r['error']) })) };
}
export function parseConfig(raw: JsonObject): RecorderConfig {
  const channels = objects(raw['channels']).map((c: JsonObject): ChannelConfig => {
    const r = objectValue(c['recording']); const d = objectValue(c['detection']);
    // 配置用于再次保存，缺失开关不能被悄悄解释成“关闭”。
    requireFields(c, ['name', 'source'], ['id', 'width', 'height', 'fps', 'preview_fps'], ['enabled'], '通道配置');
    requireFields(r, [], ['segment_minutes'], ['enabled'], '录像配置');
    requireFields(d, [], ['threshold_seconds', 'confidence', 'sample_interval', 'lost_tolerance_seconds'], ['enabled'], '检测配置');
    if (!Array.isArray(d['categories']) || (d['categories'] as Object[]).some((v: Object): boolean =>
      typeof v !== 'string' || !['person', 'vehicle', 'animal'].includes(v as string))) throw new Error('检测类别配置无效');
    const privacy = c['privacy'] === undefined ? undefined : objectValue(c['privacy']);
    if (privacy) requireFields(privacy, [], [], ['face_mosaic', 'plate_mosaic'], '隐私配置');
    const crop = numbers(c['crop']);
    if (crop.length !== 4 || crop.some((v: number): boolean => !Number.isFinite(v))) throw new Error('视频裁剪配置无效');
    return { id: numberValue(c['id']), name: textValue(c['name']), enabled: boolValue(c['enabled']), source: textValue(c['source']),
      crop: numbers(c['crop']), width: numberValue(c['width']), height: numberValue(c['height']), fps: numberValue(c['fps']), preview_fps: numberValue(c['preview_fps']),
      privacy: privacy ? { face_mosaic: boolValue(privacy['face_mosaic']), plate_mosaic: boolValue(privacy['plate_mosaic']) } : undefined,
      recording: { enabled: boolValue(r['enabled']), segment_minutes: numberValue(r['segment_minutes']) },
      detection: { enabled: boolValue(d['enabled']), categories: strings(d['categories']), threshold_seconds: numberValue(d['threshold_seconds']),
        confidence: numberValue(d['confidence']), sample_interval: numberValue(d['sample_interval']), lost_tolerance_seconds: numberValue(d['lost_tolerance_seconds']) } };
  });
  if (channels.length !== 5 || new Set<number>(channels.map((c: ChannelConfig): number => c.id)).size !== 5 ||
    channels.some((c: ChannelConfig): boolean => !Number.isInteger(c.id) || c.id < 1 || c.id > 5)) throw new Error('配置必须包含五路通道');
  const s = objectValue(raw['storage']);
  requireFields(s, ['target_id'], ['max_gb', 'min_free_gb'], [], '录像存储配置');
  return { channels: channels, storage: { target_id: textValue(s['target_id']), max_gb: numberValue(s['max_gb']),
    min_free_gb: numberValue(s['min_free_gb']) }, raw: raw };
}
