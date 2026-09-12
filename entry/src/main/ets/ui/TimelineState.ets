import { DayTimelineData, DayWindow, TimelineEvent } from '../model/Timeline';
import { RecordingItem } from '../model/Models';

/** 索引通过 ObjectLink 共享；播放时钟更新时不深拷贝一整天的记录。 */
@Observed
export class TimelineState implements DayTimelineData {
  window: DayWindow;
  recordings: RecordingItem[];
  event_segments: TimelineEvent[];
  constructor(data: DayTimelineData) {
    this.window = data.window; this.recordings = data.recordings; this.event_segments = data.event_segments;
  }
}
