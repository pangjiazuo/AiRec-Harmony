import { JsonObject, EventType, RecordingItem } from '../model/Models';
import { DayWindow, DayTimelineData, TimelineEvent, timestamp, recordingStart, recordingEnd } from '../model/Timeline';
import { parseRecordings, textValue, objects } from './JsonCodec';

/** 拒绝部分索引或错误设备的数据；不从最近 200 条推断全天。 */
export function parseTimeline(raw: JsonObject, window: DayWindow, channel: number): DayTimelineData {
  if (timestamp(textValue(raw['start'])) !== window.startMs || timestamp(textValue(raw['end'])) !== window.endMs) {
    throw new Error('录像机返回的时间范围不一致，请刷新');
  }
  if (!Array.isArray(raw['recordings']) || !Array.isArray(raw['event_segments']) ||
    (raw['recordings'] as Object[]).length > 10000 || (raw['event_segments'] as Object[]).length > 10000) {
    throw new Error('全天时间轴索引不完整或超过数量限制');
  }
  const wrapper: JsonObject = { 'items': raw['recordings'] };
  const recordings = parseRecordings(wrapper);
  recordings.forEach((item: RecordingItem): void => {
    if (item.channel_id !== channel || item.duration_seconds <= 0 ||
      !Number.isFinite(recordingEnd(item)) || recordingStart(item) >= window.endMs || recordingEnd(item) <= window.startMs) {
      throw new Error('时间轴包含错误通道或范围外录像');
    }
  });
  recordings.sort((a: RecordingItem, b: RecordingItem): number => recordingStart(a) - recordingStart(b) ||
    (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const events = objects(raw['event_segments']).map((item: JsonObject): TimelineEvent => {
    const start = textValue(item['start']); const end = textValue(item['end']); const type = textValue(item['event_type']);
    const left = timestamp(start); const right = timestamp(end);
    if (!['dwell', 'person', 'vehicle', 'animal'].includes(type) || left < window.startMs || right > window.endMs || right <= left) {
      throw new Error('时间轴事件范围或类别无效');
    }
    return { start, end, event_type: type as EventType };
  });
  return { window, recordings, event_segments: events };
}
