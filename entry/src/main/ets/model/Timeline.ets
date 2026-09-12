import { EventType, RecordingItem } from './Models';

export interface DayWindow { start: string; end: string; startMs: number; endMs: number; }
export interface TimelineEvent { start: string; end: string; event_type: EventType; }
export interface DayTimelineData { window: DayWindow; recordings: RecordingItem[]; event_segments: TimelineEvent[]; }
export interface TimeRange { start: number; end: number; }
export interface TimelineTick { at: number; label: string; }
export interface TimelinePlayback { url: string; position: number; serial: number; minPosition: number; maxPosition: number; }

/** 用翌日的本地零点，不能以固定 24 小时代替夏令时当天。 */
export function localDay(date: Date): DayWindow {
  const start = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const end = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1);
  return timeWindow(start.toISOString(), end.toISOString());
}
export function timestamp(value: string): number {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) {
    throw new Error('时间轴日期必须包含时区');
  }
  const result = new Date(value).getTime();
  const year = Number(value.substring(0, 4)); const month = Number(value.substring(5, 7));
  const day = Number(value.substring(8, 10));
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days: number[] = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (!Number.isFinite(result) || month < 1 || month > 12 || day < 1 || day > days[month - 1] ||
    Number(value.substring(11, 13)) > 23 || Number(value.substring(14, 16)) > 59 || Number(value.substring(17, 19)) > 59) {
    throw new Error('时间轴日期无效');
  }
  return result;
}
export function timeWindow(start: string, end: string): DayWindow {
  const startMs = timestamp(start); const endMs = timestamp(end);
  const hours = (endMs - startMs) / 3600000;
  if (hours < 23 || hours > 25) throw new Error('时间轴仅支持一个本地自然日');
  return { start, end, startMs, endMs };
}
export function emptyTimeline(window: DayWindow): DayTimelineData { return { window, recordings: [], event_segments: [] }; }
export function recordingStart(item: RecordingItem): number {
  const text = item.created_at.replace(' ', 'T');
  // 旧数据库的无时区时间与服务端一致解释为 UTC，不能使用手机本地时区。
  return timestamp(/(?:Z|[+-]\d{2}:\d{2})$/.test(text) ? text : `${text}Z`);
}
export function recordingEnd(item: RecordingItem): number { return recordingStart(item) + item.duration_seconds * 1000; }
export function clipped(start: number, end: number, window: DayWindow): TimeRange | undefined {
  const left = Math.max(start, window.startMs); const right = Math.min(end, window.endMs);
  return right > left ? { start: left, end: right } : undefined;
}
export function recordingAt(data: DayTimelineData, at: number): RecordingItem | undefined {
  if (at < data.window.startMs || at >= data.window.endMs) return undefined;
  return data.recordings.find((item: RecordingItem): boolean => item.available &&
    recordingStart(item) <= at && at < recordingEnd(item));
}
/** 重叠片段可能有共同起点，优先使用已排序的第一个能覆盖当前位置的片段。 */
export function continuation(data: DayTimelineData, current: RecordingItem): RecordingItem | undefined {
  const at = recordingEnd(current);
  if (at >= data.window.endMs) return undefined;
  return data.recordings.find((item: RecordingItem): boolean => item.id !== current.id && item.available &&
    recordingStart(item) <= at && recordingEnd(item) > at);
}
export function recordingRanges(data: DayTimelineData): TimeRange[] {
  const ranges: TimeRange[] = [];
  data.recordings.forEach((item: RecordingItem): void => {
    if (!item.available) return;
    const range = clipped(recordingStart(item), recordingEnd(item), data.window);
    if (!range) return;
    const previous = ranges.length > 0 ? ranges[ranges.length - 1] : undefined;
    if (previous && range.start <= previous.end) previous.end = Math.max(previous.end, range.end);
    else ranges.push(range);
  });
  return ranges;
}
function pad(value: number): string { return value.toString().padStart(2, '0'); }
export function clockText(at: number, window: DayWindow): string {
  if (at >= window.endMs) return '24:00:00';
  const date = new Date(Math.max(window.startMs, at));
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}
export function timezoneText(at: number): string {
  const offset = -new Date(at).getTimezoneOffset();
  return `UTC${offset >= 0 ? '+' : '-'}${pad(Math.floor(Math.abs(offset) / 60))}:${pad(Math.abs(offset) % 60)}`;
}
export function timelineTicks(window: DayWindow, step: number = 3600000): TimelineTick[] {
  const result: TimelineTick[] = [];
  const unusual = window.endMs - window.startMs !== 86400000;
  for (let at = window.startMs; at < window.endMs; at += step) {
    const date = new Date(at);
    result.push({ at, label: `${pad(date.getHours())}:${pad(date.getMinutes())}${unusual ? ` ${timezoneText(at)}` : ''}` });
  }
  result.push({ at: window.endMs, label: '24:00' });
  return result;
}
