import { ChannelPatch, ConfigChanges, JsonObject, RecorderConfig } from '../model/Models';
import { objectValue, objects, numberValue, parseConfig, parseObject } from './JsonCodec';

function range(value: number, min: number, max: number, label: string, integer: boolean = false): void {
  if (!Number.isFinite(value) || value < min || value > max || (integer && !Number.isInteger(value))) {
    throw new Error(`${label}范围应为 ${min}～${max}`);
  }
}

/** 只合并界面明确编辑的字段，保留最新配置的 id/source/crop 和所有未知字段。 */
export function mergeConfigChanges(latest: RecorderConfig, changes: ConfigChanges): RecorderConfig {
  const raw = parseObject(JSON.stringify(latest.raw));
  const channels = objects(raw['channels']);
  const seen = new Set<number>();
  changes.channels?.forEach((patch: ChannelPatch): void => {
    range(patch.id, 1, 5, '通道编号', true);
    if (seen.has(patch.id)) throw new Error('通道编号不能重复'); seen.add(patch.id);
    const c = channels.find((item: JsonObject): boolean => numberValue(item['id']) === patch.id);
    if (!c) throw new Error('通道不存在');
    if (patch.name !== undefined) c['name'] = patch.name.trim();
    if (patch.enabled !== undefined) c['enabled'] = patch.enabled;
    if (patch.width !== undefined) c['width'] = patch.width;
    if (patch.height !== undefined) c['height'] = patch.height;
    if (patch.fps !== undefined) c['fps'] = patch.fps;
    if (patch.preview_fps !== undefined) c['preview_fps'] = patch.preview_fps;
    if (patch.privacy) {
      const p = objectValue(c['privacy']);
      if (patch.privacy.face_mosaic !== undefined) p['face_mosaic'] = patch.privacy.face_mosaic;
      if (patch.privacy.plate_mosaic !== undefined) p['plate_mosaic'] = patch.privacy.plate_mosaic;
      c['privacy'] = p;
    }
    if (patch.recording) {
      const r = objectValue(c['recording']);
      if (patch.recording.enabled !== undefined) r['enabled'] = patch.recording.enabled;
      if (patch.recording.segment_minutes !== undefined) r['segment_minutes'] = patch.recording.segment_minutes;
      c['recording'] = r;
    }
    if (patch.detection) {
      const d = objectValue(c['detection']); const p = patch.detection;
      if (p.enabled !== undefined) d['enabled'] = p.enabled;
      if (p.categories !== undefined) d['categories'] = p.categories.slice();
      if (p.threshold_seconds !== undefined) d['threshold_seconds'] = p.threshold_seconds;
      if (p.confidence !== undefined) d['confidence'] = p.confidence;
      if (p.sample_interval !== undefined) d['sample_interval'] = p.sample_interval;
      if (p.lost_tolerance_seconds !== undefined) d['lost_tolerance_seconds'] = p.lost_tolerance_seconds;
      c['detection'] = d;
    }
  });
  raw['channels'] = channels;
  if (changes.storage) {
    const s = objectValue(raw['storage']); const p = changes.storage;
    if (p.target_id !== undefined) s['target_id'] = p.target_id;
    if (p.max_gb !== undefined) s['max_gb'] = p.max_gb;
    if (p.min_free_gb !== undefined) s['min_free_gb'] = p.min_free_gb;
    raw['storage'] = s;
  }
  const result = parseConfig(raw);
  result.channels.forEach((c): void => {
    if (c.name.length < 1 || c.name.length > 40) throw new Error('通道名称长度应为 1～40');
    range(c.width, 160, 1920, '宽度', true); range(c.height, 120, 1080, '高度', true);
    if (c.width % 8 !== 0 || c.height % 8 !== 0) throw new Error('宽高须为 8 的整数倍');
    range(c.fps, 1, 30, '录像帧率', true); range(c.preview_fps, 1, c.fps, '预览帧率', true);
    if (![1, 3, 5, 10].includes(c.recording.segment_minutes)) throw new Error('录像片段只能为 1、3、5、10 分钟');
    const d = c.detection;
    if (d.categories.some((v: string): boolean => !['person', 'vehicle', 'animal'].includes(v))) throw new Error('识别类别无效');
    range(d.threshold_seconds, 0.1, 3600, '停留阈值'); range(d.confidence, 0.1, 0.99, '置信度');
    range(d.sample_interval, 0.2, 10, '侦测间隔'); range(d.lost_tolerance_seconds, 0.2, 30, '消失容忍时间');
    if (d.lost_tolerance_seconds < d.sample_interval) throw new Error('消失容忍时间不能小于侦测间隔');
  });
  range(result.storage.max_gb, 1, 100000, '录像空间上限'); range(result.storage.min_free_gb, 0.25, 10000, '保留空间');
  if (!/^(internal|uuid:[A-Za-z0-9_-]{1,128})$/.test(result.storage.target_id)) throw new Error('保存介质标识无效');
  return result;
}
