export class Palette {
  static readonly background: Resource = $r('app.color.recorder_bg');
  static readonly card: Resource = $r('app.color.recorder_card');
  static readonly text: Resource = $r('app.color.recorder_text');
  static readonly secondary: Resource = $r('app.color.recorder_secondary');
  static readonly line: Resource = $r('app.color.recorder_line');
  static readonly brand: Resource = $r('app.color.recorder_brand');
  static readonly preview: Resource = $r('app.color.recorder_preview');
}

export function metric(value: number, suffix: string = ''): string {
  return Number.isFinite(value) ? `${value.toFixed(1)}${suffix}` : '—';
}
export function bytesText(value: number): string {
  if (!Number.isFinite(value) || value < 0) return '—';
  return value >= 1073741824 ? `${(value / 1073741824).toFixed(1)} GB` : `${(value / 1048576).toFixed(1)} MB`;
}
export function dateText(value: string): string {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return value;
  return `${date.getMonth() + 1}月${date.getDate()}日 ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}
export function dayKey(value: string): string {
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` : '';
}
export function pad(value: number): string { return value.toString().padStart(2, '0'); }
export function eventName(type: string): string {
  if (type === 'dwell') return '长时间停留';
  if (type === 'person') return '人出现';
  if (type === 'vehicle') return '车出现';
  if (type === 'animal') return '动物出现';
  return '事件';
}
export function eventColor(type: string): string {
  if (type === 'dwell') return '#E65B65';
  if (type === 'vehicle') return '#A478E3';
  if (type === 'animal') return '#39AE83';
  return '#4E92F7';
}

@Component
export struct Notice {
  @Prop text: string = '';
  build() {
    if (this.text.length > 0) {
      Text(this.text).fontSize(14).fontColor(Palette.secondary).width('100%')
        .padding(16).backgroundColor(Palette.card).borderRadius(16).id('notice');
    }
  }
}
