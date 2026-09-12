import { RecordingItem, JsonObject } from '../model/Models';
import { DayTimelineData, timeWindow, localDay, timestamp, recordingStart, recordingAt, recordingRanges,
  continuation, clipped, clockText, timelineTicks } from '../model/Timeline';
import { parseTimeline } from './TimelineCodec';

export interface TimelineCheckResult { name: string; passed: boolean; error: string; }
function check(value: boolean, message: string): void { if (!value) throw new Error(message); }
function rejects(action: () => void): void {
  let failed = false; try { action(); } catch (_) { failed = true; }
  check(failed, '无效索引未被拒绝');
}
function item(id: string, start: string, seconds: number = 60, available: boolean = true): RecordingItem {
  return { id, channel_id: 1, created_at: start, duration_seconds: seconds, size_bytes: 1024,
    url: `/media/${id}.mp4`, available, error: '' };
}
function raw(items: RecordingItem[]): JsonObject {
  return { 'start': '2026-09-07T16:00:00Z', 'end': '2026-09-08T16:00:00Z', 'recordings': items, 'event_segments': [] };
}

/** 可由原生隔离入口执行，固定时区用例不依赖测试设备的时区设置。 */
export function runTimelineChecks(): TimelineCheckResult[] {
  const results: TimelineCheckResult[] = [];
  const run = (name: string, action: () => void): void => {
    try { action(); results.push({ name, passed: true, error: '' }); }
    catch (error) { results.push({ name, passed: false, error: (error as Error).message }); }
  };
  const window = timeWindow('2026-09-08T00:00:00+08:00', '2026-09-09T00:00:00+08:00');
  run('时间轴：本地自然日与 23/25 小时窗口', (): void => {
    const local = localDay(new Date(2026, 8, 8, 12));
    check(new Date(local.startMs).getHours() === 0 && new Date(local.endMs).getDate() === 9, '自然日端点错误');
    const winterOffset = new Date(2026, 0, 1).getTimezoneOffset();
    const summerOffset = new Date(2026, 6, 1).getTimezoneOffset();
    if (winterOffset === 300 && summerOffset === 240) {
      const springDay = localDay(new Date(2026, 2, 8)); const fallDay = localDay(new Date(2026, 10, 1));
      check(springDay.endMs - springDay.startMs === 23 * 3600000 && fallDay.endMs - fallDay.startMs === 25 * 3600000,
        '纽约 localDay 不能硬编码为 24 小时');
    }
    if (winterOffset === -60 && summerOffset === -120) {
      const springDay = localDay(new Date(2026, 2, 29)); const fallDay = localDay(new Date(2026, 9, 25));
      check(springDay.endMs - springDay.startMs === 23 * 3600000 && fallDay.endMs - fallDay.startMs === 25 * 3600000,
        '柏林 localDay 不能硬编码为 24 小时');
    }
    const short = timeWindow('2026-03-08T00:00:00-05:00', '2026-03-09T00:00:00-04:00');
    const long = timeWindow('2026-11-01T00:00:00-04:00', '2026-11-02T00:00:00-05:00');
    check(short.endMs - short.startMs === 23 * 3600000 && long.endMs - long.startMs === 25 * 3600000, 'DST 窗口错误');
    check(timelineTicks(short).length === 24 && timelineTicks(long).length === 26, '实际时间轴刻度缺失');
    rejects((): void => { timeWindow('2026-09-08T00:00:00Z', '2026-09-10T00:00:00Z'); });
  });
  run('时间轴：时区与无效日期', (): void => {
    check(timestamp(window.start) === timestamp('2026-09-07T16:00:00.000000Z'), '等价时区没有对齐');
    check(recordingStart(item('old', '2026-09-08T00:00:00')) === timestamp('2026-09-08T00:00:00Z'), '旧日期没有按 UTC 解释');
    rejects((): void => { timestamp('2026-09-08T00:00:00'); });
    rejects((): void => { timestamp('2026-02-30T00:00:00Z'); });
    rejects((): void => { timestamp('2026-09-08T24:00:00Z'); });
  });
  run('时间轴：跨午夜裁剪且 24 点排他', (): void => {
    const previous = item('cross', '2026-09-07T23:59:30+08:00', 60);
    const data = parseTimeline(raw([previous]), window, 1);
    const range = recordingRanges(data)[0];
    check(range.start === window.startMs && range.end === window.startMs + 30000, '跨日裁剪错误');
    check(data.recordings[0].duration_seconds === 60 && recordingStart(data.recordings[0]) < window.startMs, '原片段被改写');
    check(recordingAt(data, window.startMs)?.id === 'cross', '00:00 未命中跨日片段');
    check(recordingAt(data, window.startMs + 30000) === undefined && recordingAt(data, window.endMs) === undefined, '右端点应排他');
    check(clockText(window.endMs, window) === '24:00:00' && clipped(window.endMs, window.endMs + 1000, window) === undefined, '24 点越界');
    const last = item('last', '2026-09-08T23:59:30+08:00', 60);
    const endData = parseTimeline(raw([last]), window, 1);
    check(recordingRanges(endData)[0].end === window.endMs && continuation(endData, last) === undefined,
      '跨出当日的片段必须在 24 点停止');
  });
  run('时间轴：连续片段续播、重叠和空白不跳播', (): void => {
    const first = item('a', '2026-09-08T12:00:00+08:00');
    const next = item('b', '2026-09-08T12:01:00+08:00');
    const gap = item('c', '2026-09-08T12:02:01+08:00');
    const data = parseTimeline(raw([gap, first, next]), window, 1);
    check(continuation(data, first)?.id === 'b', '相接未续播');
    check(continuation(data, next) === undefined, '错误跨过 1 秒空白');
    check(recordingAt(data, timestamp('2026-09-08T12:02:00.500Z') - 8 * 3600000) === undefined, '空白错误命中');
    const overlap = parseTimeline(raw([first, item('overlap', '2026-09-08T12:00:30+08:00', 90)]), window, 1);
    check(continuation(overlap, first)?.id === 'overlap' && recordingRanges(overlap).length === 1, '重叠未合并或续播');
  });
  run('时间轴：已清理录像保留索引但不能播放', (): void => {
    const removed = item('gone', '2026-09-08T12:00:00+08:00', 60, false);
    const data = parseTimeline(raw([removed]), window, 1);
    check(data.recordings.length === 1 && recordingRanges(data).length === 0 && recordingAt(data, recordingStart(removed)) === undefined, '已清理录像被播放');
  });
  run('时间轴：全天超过 200 条仍完整', (): void => {
    const items: RecordingItem[] = [];
    for (let i = 0; i < 1440; i++) items.push(item(`minute-${i}`, new Date(window.startMs + i * 60000).toISOString()));
    const data = parseTimeline(raw(items), window, 1);
    check(data.recordings.length === 1440 && recordingAt(data, window.startMs + 1000)?.id === 'minute-0' &&
      recordingAt(data, window.endMs - 1000)?.id === 'minute-1439', '全天被截为最近 200 条');
    check(recordingRanges(data).length === 1 && recordingRanges(data)[0].end === window.endMs, '全天色带不完整');
  });
  run('时间轴：错误范围、通道、重复和缺失索引拒绝', (): void => {
    const one = item('a', '2026-09-08T12:00:00+08:00');
    const shifted = raw([one]); shifted['end'] = '2026-09-08T15:00:00Z';
    rejects((): void => { parseTimeline(shifted, window, 1); });
    rejects((): void => { parseTimeline(raw([one]), window, 2); });
    rejects((): void => { parseTimeline(raw([one, one]), window, 1); });
    const missing = raw([]); missing['recordings'] = 'missing';
    rejects((): void => { parseTimeline(missing, window, 1); });
    rejects((): void => { parseTimeline(raw([item('outside', '2026-09-09T00:00:00+08:00')]), window, 1); });
  });
  run('时间轴：四类事件及真实区间校验', (): void => {
    const data = raw([]); const events: JsonObject[] = [];
    ['dwell', 'person', 'vehicle', 'animal'].forEach((type: string): void => {
      events.push({ 'start': '2026-09-08T04:00:00Z', 'end': '2026-09-08T04:00:01Z', 'event_type': type });
    });
    data['event_segments'] = events;
    check(parseTimeline(data, window, 1).event_segments.length === 4, '事件类别丢失');
    events[0]['event_type'] = 'invalid'; rejects((): void => { parseTimeline(data, window, 1); });
    events[0]['event_type'] = 'dwell'; events[0]['end'] = events[0]['start'];
    rejects((): void => { parseTimeline(data, window, 1); });
  });
  return results;
}
