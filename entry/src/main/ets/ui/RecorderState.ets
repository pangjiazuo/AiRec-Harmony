import { RecorderApi } from '../data/RecorderApi';
import { ChannelStatus, RecorderStatus, emptyStatus } from '../model/Models';

export interface RouteData { channel: number; url: string; title: string; position: number; recordedAt: string; }
export function routeData(channel: number = 0, url: string = '', title: string = '', position: number = 0,
  recordedAt: string = ''): RouteData { return { channel, url, title, position, recordedAt }; }

/** 单次轮询完成后才安排下一次；换地址/进后台后旧请求不能覆盖新状态。 */
@Observed
export class RecorderState {
  endpoint: string = 'http://192.168.10.172:8080';
  status: RecorderStatus = emptyStatus();
  connected: boolean = false;
  message: string = '正在连接录像机…';
  route: string = 'live';
  foreground: boolean = true;
  appearance: string = 'light';
  private timer: number = -1;
  private generation: number = 0;
  private request?: RecorderApi = undefined;

  api(): RecorderApi { return new RecorderApi(this.endpoint); }
  previewMessage(id: number): string {
    if (!this.connected) return '等待设备连接';
    return !this.channel(id).enabled || this.channel(id).state === 'disabled' ? '通道已关闭' : '暂无信号';
  }
  channel(id: number): ChannelStatus {
    const found = this.status.channels.find((item: ChannelStatus) => item.id === id);
    return found ?? { id, name: `AHD${id}`, enabled: true, state: 'connecting', recording: false,
      preview_fps: NaN, recording_fps: NaN, capture_fps: NaN, detections: [], error: '' };
  }
  start(): void { this.cancelPolling(); this.foreground = true; this.poll(this.generation); }
  stop(): void { this.foreground = false; this.cancelPolling(); }
  private cancelPolling(): void {
    this.generation++; this.request?.cancelAll(); this.request = undefined;
    if (this.timer >= 0) clearTimeout(this.timer); this.timer = -1;
  }
  connect(endpoint: string): void {
    this.endpoint = endpoint; this.status = emptyStatus(); this.connected = false; this.message = '正在连接录像机…';
    this.start();
  }
  private async poll(generation: number): Promise<void> {
    try {
      this.request = this.api();
      const status = await this.request.getStatus();
      if (generation !== this.generation) return;
      this.status = status; this.connected = true; this.message = '';
    } catch (error) {
      if (generation !== this.generation) return;
      this.connected = false; this.message = '连接已中断，正在自动重连…';
    }
    if (generation === this.generation && this.foreground) {
      this.timer = setTimeout(() => this.poll(generation), this.connected ? 2000 : 3000);
    }
  }
}
