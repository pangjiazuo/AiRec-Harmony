import { RecorderApi, normalizeEndpoint } from './RecorderApi';
import { mergeConfigChanges } from './ConfigMerge';
import { parseConfig, parseObject, parseStatus, parseRecordings, parseEvents, parseTargets, parseModel,
  objectValue, objects, numberValue, textValue } from './JsonCodec';
import { RecorderConfig, JsonObject, ConfigChanges } from '../model/Models';
import { MjpegParser } from '../media/MjpegParser';
import { runTimelineChecks } from './TimelineChecks';

export interface LogicCheckResult { name: string; passed: boolean; error: string; }
function assert(condition: boolean, message: string): void { if (!condition) throw new Error(message); }
function expectFailure(action: () => void): void {
  let failed = false; try { action(); } catch (_) { failed = true; }
  assert(failed, '应当拒绝无效输入');
}
function bytes(text: string): Uint8Array {
  const result = new Uint8Array(text.length); for (let i = 0; i < text.length; i++) result[i] = text.charCodeAt(i); return result;
}
function fixture(): RecorderConfig {
  const channels: string[] = [];
  for (let i = 1; i <= 5; i++) channels.push(`{"id":${i},"name":"AHD${i}","enabled":true,"source":"/dev/video${i}",
    "crop":[0,0,1,1],"width":1280,"height":720,"fps":25,"preview_fps":16,"future":{"keep":"yes"},
    "recording":{"enabled":true,"segment_minutes":5,"extension":7},"detection":{"enabled":true,"categories":["person","vehicle","animal"],
    "threshold_seconds":10,"confidence":0.8,"sample_interval":1,"lost_tolerance_seconds":2}}`);
  return parseConfig(parseObject(`{"channels":[${channels.join(',')}],"storage":{"target_id":"internal","max_gb":24,"min_free_gb":3,"future":"keep"},
    "server":{"host":"0.0.0.0","port":8080},"future":{"version":7}}`));
}

/** 由隔离测试入口调用；仅构造内存数据，不访问开发板、不保存真实配置。 */
export function runLogicChecks(): LogicCheckResult[] {
  const results: LogicCheckResult[] = [];
  const run = (name: string, check: () => void): void => {
    try { check(); results.push({ name: name, passed: true, error: '' }); }
    catch (error) { results.push({ name: name, passed: false, error: (error as Error).message }); }
  };
  run('隐私开关独立合并且保留其他通道', (): void => {
    const before = fixture();
    const updated = mergeConfigChanges(before, { channels: [{ id: 1, privacy: { face_mosaic: true, plate_mosaic: false } }] });
    assert(updated.channels[0].privacy?.face_mosaic === true, '人脸开关丢失');
    assert(updated.channels[0].privacy?.plate_mosaic === false, '车牌开关丢失');
    assert(updated.channels[1].privacy === undefined && before.channels[0].privacy === undefined, '修改影响了其他通道或原配置');
  });
  run('地址规范化与同源媒体', (): void => {
    assert(normalizeEndpoint(' 192.168.10.172:8080/ ') === 'http://192.168.10.172:8080', '默认地址解析失败');
    const api = new RecorderApi('http://127.0.0.1:18080');
    assert(api.mediaUrl('/media/a.mp4') === 'http://127.0.0.1:18080/media/a.mp4', '媒体地址错误');
    expectFailure((): void => { normalizeEndpoint('http://user:password@board'); });
    expectFailure((): void => { normalizeEndpoint('http://board/path'); });
    expectFailure((): void => { api.mediaUrl('https://example.com/media/a.mp4'); });
  });
  run('最新配置合并保留未知字段与其他通道', (): void => {
    const latest = fixture(); const rawChannels = objects(latest.raw['channels']);
    rawChannels[1]['name'] = '另一客户端修改的后门'; latest.raw['channels'] = rawChannels;
    const changes: ConfigChanges = { channels: [{ id: 1, detection: { threshold_seconds: 17 } }] };
    const result = mergeConfigChanges(latest, changes);
    const first = objects(result.raw['channels'])[0];
    assert(result.channels[0].detection.threshold_seconds === 17, '编辑值未应用');
    assert(result.channels[1].name === '另一客户端修改的后门', '覆盖其他客户端改动');
    assert(result.channels[0].source === '/dev/video1' && result.channels[0].crop.join(',') === '0,0,1,1', '硬件映射被覆盖');
    assert(textValue(objectValue(first['future'])['keep']) === 'yes', '通道未知字段丢失');
    assert(numberValue(objectValue(first['recording'])['extension']) === 7, '嵌套未知字段丢失');
    assert(textValue(objectValue(result.raw['storage'])['future']) === 'keep', '存储未知字段丢失');
    assert(numberValue(objectValue(result.raw['future'])['version']) === 7, '顶层未知字段丢失');
    assert(latest.channels[0].detection.threshold_seconds === 10, '合并修改了输入对象');
  });
  run('复制部分参数保留名称和接线', (): void => {
    const changes: ConfigChanges = { channels: [
      { id: 2, recording: { segment_minutes: 3 }, detection: { threshold_seconds: 15 } },
      { id: 3, recording: { segment_minutes: 3 }, detection: { threshold_seconds: 15 } }] };
    const result = mergeConfigChanges(fixture(), changes);
    assert(result.channels[1].recording.segment_minutes === 3 && result.channels[2].detection.threshold_seconds === 15, '复制未生效');
    assert(result.channels[1].name === 'AHD2' && result.channels[2].source === '/dev/video3', '复制破坏通道身份');
    assert(result.channels[0].recording.segment_minutes === 5, '修改了未选通道');
  });
  run('配置范围和关联条件校验', (): void => {
    expectFailure((): void => { mergeConfigChanges(fixture(), { channels: [{ id: 1, detection: { threshold_seconds: 0 } }] }); });
    expectFailure((): void => { mergeConfigChanges(fixture(), { channels: [{ id: 1, preview_fps: 30 }] }); });
    expectFailure((): void => { mergeConfigChanges(fixture(), { channels: [{ id: 1, detection: { sample_interval: 5 } }] }); });
    expectFailure((): void => { mergeConfigChanges(fixture(), { channels: [{ id: 1 }, { id: 1 }] }); });
  });
  run('缺少遥测不伪装成零', (): void => {
    const status = parseStatus(parseObject('{"channels":[]}'));
    assert(!Number.isFinite(status.system.cpu_percent) && !Number.isFinite(status.storage.free_bytes), '未知遥测应为NaN');
    expectFailure((): void => { parseStatus(parseObject('{"channels":[{"id":1},{"id":1}]}')); });
  });
  run('不完整配置不能被解释成关闭或清空', (): void => {
    const wrongBoolean = fixture().raw; objects(wrongBoolean['channels'])[0]['enabled'] = 'false';
    expectFailure((): void => { parseConfig(wrongBoolean); });
    const noRecording = fixture().raw; objects(noRecording['channels'])[0]['recording'] = {} as JsonObject;
    expectFailure((): void => { parseConfig(noRecording); });
    const noStorage = fixture().raw; noStorage['storage'] = {} as JsonObject;
    expectFailure((): void => { parseConfig(noStorage); });
    const emptyCategories = fixture().raw;
    objectValue(objects(emptyCategories['channels'])[0]['detection'])['categories'] = [];
    assert(parseConfig(emptyCategories).channels[0].detection.categories.length === 0, '合法的空识别类别应保留');
  });
  run('录像清理与不完整事件列表', (): void => {
    const recording = '{"id":"r1","channel_id":1,"created_at":"2026-09-08T12:00:00+08:00","duration_seconds":60,"size_bytes":1024,"url":"/media/r1.mp4","available":false}';
    const removed = parseRecordings(parseObject(`{"items":[${recording}]}`));
    assert(removed.length === 1 && !removed[0].available, '已清理录像应保留不可用信息');
    expectFailure((): void => { parseRecordings(parseObject('{"items":[{}]}')); });
    expectFailure((): void => { parseRecordings(parseObject(`{"items":[${recording},${recording}]}`)); });
    const events = parseEvents(parseObject('{"items":[{"id":"e1","channel_id":1,"created_at":"2026-09-08T12:00:00+08:00","event_type":"person","category":"person","dwell_seconds":0,"snapshot_url":"/media/e1.jpg"}]}'));
    assert(events.length === 1 && !events[0].recording_available && events[0].recording_url === '', '尚未封装关联录像不应判为事件失败');
    expectFailure((): void => { parseEvents(parseObject('{"items":[{}]}')); });
  });
  run('模型和介质缺失不能伪装成空状态', (): void => {
    expectFailure((): void => { parseModel({} as JsonObject); });
    expectFailure((): void => { parseTargets({} as JsonObject); });
    expectFailure((): void => { parseTargets(parseObject('{"targets":[{"id":"internal"}]}')); });
    const targets = parseTargets(parseObject('{"targets":[{"id":"uuid:missing","available":false,"writable":false}]}'));
    assert(!targets.targets[0].available && !Number.isFinite(targets.targets[0].free_bytes), '拔出的介质保留不可用和未知容量');
  });
  run('MJPEG碎片头部与连续多帧', (): void => {
    let count = 0;
    const parser = new MjpegParser((jpeg: ArrayBuffer): void => { assert(jpeg.byteLength === 6, '帧长度错误'); count++; });
    const header = bytes('--frame\r\nContent-Type: image/jpeg\r\nContent-Length: 6\r\n\r\n');
    const jpeg = new Uint8Array([255, 216, 1, 2, 255, 217]);
    for (let n = 0; n < 2; n++) {
      for (let i = 0; i < header.length; i++) parser.feed(header.slice(i, i + 1).buffer as ArrayBuffer);
      parser.feed(jpeg.slice(0, 3).buffer as ArrayBuffer); parser.feed(jpeg.slice(3).buffer as ArrayBuffer);
      parser.feed(bytes('\r\n').buffer as ArrayBuffer);
    }
    assert(count === 2, '连续帧丢失');
  });
  run('MJPEG无效长度损坏图片与超长头部', (): void => {
    expectFailure((): void => { new MjpegParser((_: ArrayBuffer): void => {}).feed(bytes('--f\r\nContent-Length: 4194305\r\n\r\n').buffer as ArrayBuffer); });
    expectFailure((): void => { new MjpegParser((_: ArrayBuffer): void => {}).feed(bytes('--f\r\nContent-Length: 4\r\n\r\nabcd').buffer as ArrayBuffer); });
    expectFailure((): void => { new MjpegParser((_: ArrayBuffer): void => {}).feed(new Uint8Array(9000).buffer as ArrayBuffer); });
  });
  return results.concat(runTimelineChecks());
}
