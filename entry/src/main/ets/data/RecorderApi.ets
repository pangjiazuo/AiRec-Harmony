import { http } from '@kit.NetworkKit';
import { url, util } from '@kit.ArkTS';
import { ConfigChanges, JsonObject, RecorderStatus, RecorderConfig, RecordingItem, EventItem, ModelInfo,
  StorageTargets, SaveConfigResult } from '../model/Models';
import { parseObject, parseStatus, parseRecordings, parseEvents, parseConfig, parseModel, parseTargets,
  objectValue, boolValue, textValue } from './JsonCodec';
import { mergeConfigChanges } from './ConfigMerge';
import { DayWindow, DayTimelineData } from '../model/Timeline';
import { parseTimeline } from './TimelineCodec';

export const DEFAULT_ENDPOINT: string = 'http://192.168.10.172:8080';
export function normalizeEndpoint(input: string): string {
  const value = input.trim();
  if (value.length === 0 || /[\s\\]/.test(value)) throw new Error('请输入有效录像机地址');
  const address = url.URL.parseURL(value.includes('://') ? value : `http://${value}`);
  if (!['http:', 'https:'].includes(address.protocol) || !address.hostname || address.username || address.password ||
    (address.pathname !== '' && address.pathname !== '/') || address.search || address.hash) {
    throw new Error('仅支持录像机 HTTP/HTTPS 地址，不包含账号、路径或参数');
  }
  return address.origin;
}
export function headerText(headers: Object, name: string): string {
  const values = headers as JsonObject;
  const key = Object.keys(values).find((item: string): boolean => item.toLowerCase() === name.toLowerCase());
  return key === undefined ? '' : `${values[key]}`;
}
export function headerStatus(headers: Object): number {
  const matched = /\s(\d{3})(?:\s|$)/.exec(headerText(headers, 'status-line'));
  return matched ? Number(matched[1]) : 0;
}
export function responseError(status: number): string {
  if (status === 404) return '文件不存在或已被循环清理';
  if (status === 503) return '通道暂无信号或连接繁忙';
  return `请求失败（HTTP ${status}）`;
}
export function readableError(error: Error): string { return error.message || '连接失败，请检查录像机地址与网络'; }

export class RecorderApi {
  readonly baseUrl: string;
  private requests: Set<http.HttpRequest> = new Set<http.HttpRequest>();
  private generation: number = 0;
  constructor(endpoint: string = DEFAULT_ENDPOINT) { this.baseUrl = normalizeEndpoint(endpoint); }
  static normalizeEndpoint(input: string): string { return normalizeEndpoint(input); }
  mediaUrl(path: string): string {
    if (!path || /[\s\\]/.test(path) || path.startsWith('//')) throw new Error('媒体地址无效');
    const resolved = url.URL.parseURL(path, `${this.baseUrl}/`);
    if (resolved.origin !== this.baseUrl || resolved.username || resolved.password || resolved.hash) throw new Error('媒体地址必须来自当前录像机');
    return resolved.href;
  }
  cancelAll(): void {
    this.generation++;
    this.requests.forEach((request: http.HttpRequest): void => { try { request.destroy(); } catch (_) {} });
    this.requests.clear();
  }
  async getStatus(): Promise<RecorderStatus> { return parseStatus(await this.getJson('/api/status')); }
  async getConfig(): Promise<RecorderConfig> { return parseConfig(await this.getJson('/api/config')); }
  async getRecordings(channel?: number): Promise<RecordingItem[]> {
    const items = parseRecordings(await this.getJson(`/api/recordings${this.channelQuery(channel)}`));
    items.forEach((item: RecordingItem): void => { this.mediaUrl(item.url); });
    return items;
  }
  async getTimeline(channel: number, window: DayWindow): Promise<DayTimelineData> {
    const query = this.channelQuery(channel);
    if (!query) throw new Error('时间轴需要选择单路通道');
    const raw = await this.requestJson(`/api/timeline${query}&start=${encodeURIComponent(window.start)}&end=${encodeURIComponent(window.end)}`,
      http.RequestMethod.GET);
    const result = parseTimeline(raw, window, channel);
    result.recordings.forEach((item: RecordingItem): void => { this.mediaUrl(item.url); });
    return result;
  }
  async getEvents(channel?: number, event?: string): Promise<EventItem[]> {
    let query = this.channelQuery(channel);
    if (event) {
      if (!['person', 'vehicle', 'animal', 'dwell'].includes(event)) throw new Error('事件类别无效');
      query += `${query ? '&' : '?'}event_type=${event}`;
    }
    const items = parseEvents(await this.getJson(`/api/events${query}`));
    items.forEach((item: EventItem): void => {
      this.mediaUrl(item.snapshot_url); if (item.recording_url) this.mediaUrl(item.recording_url);
    });
    return items;
  }
  async getModel(): Promise<ModelInfo> { return parseModel(await this.getJson('/api/diagnostics/model')); }
  async getStorageTargets(): Promise<StorageTargets> { return parseTargets(await this.getJson('/api/storage/targets')); }
  async getLogs(): Promise<JsonObject> { return this.getJson('/api/logs'); }
  async saveConfigChanges(changes: ConfigChanges): Promise<SaveConfigResult> {
    const token = this.generation;
    const latest = await this.getConfig();
    this.checkActive(token);
    const merged = mergeConfigChanges(latest, changes);
    if (merged.storage.target_id !== latest.storage.target_id) {
      const targets = await this.getStorageTargets();
      this.checkActive(token);
      if (!targets.targets.some((t): boolean => t.id === merged.storage.target_id && t.available && t.writable)) {
        throw new Error('所选保存介质当前不可用，请刷新后重试');
      }
    }
    const body = JSON.stringify(merged.raw);
    if (new util.TextEncoder().encodeInto(body).byteLength > 65536) throw new Error('配置超过接口大小限制');
    // 取消读取后不能继续下一步 PUT；已经发出的 PUT 仍以服务器实际结果为准。
    this.checkActive(token);
    const result = await this.requestJson('/api/config', http.RequestMethod.PUT, body);
    this.checkActive(token);
    if (!boolValue(result['ok'])) throw new Error(textValue(result['error'], '尚未确认配置保存成功'));
    return { ok: true, config: parseConfig(objectValue(result['config'])), restart_required: boolValue(result['restart_required']) };
  }
  async getJson(path: string): Promise<JsonObject> { return this.requestJson(path, http.RequestMethod.GET); }
  private checkActive(token: number): void { if (token !== this.generation) throw new Error('请求已取消'); }
  private channelQuery(channel?: number): string {
    if (channel === undefined || channel === 0) return '';
    if (!Number.isInteger(channel) || channel < 1 || channel > 5) throw new Error('通道编号应为 1～5');
    return `?channel_id=${channel}`;
  }
  private async requestJson(path: string, method: http.RequestMethod, body?: string): Promise<JsonObject> {
    const token = this.generation;
    const request = http.createHttp(); this.requests.add(request);
    let redirect = false;
    request.on('headersReceive', (headers: Object): void => {
      const code = headerStatus(headers);
      if (code >= 300 && code < 400) { redirect = true; try { request.destroy(); } catch (_) {} }
    });
    const headers: Record<string, string> = { 'Accept': 'application/json', 'Content-Type': 'application/json' };
    const options: http.HttpRequestOptions = { method: method, expectDataType: http.HttpDataType.STRING,
      usingCache: false, usingProxy: false, header: headers, readTimeout: 8000, connectTimeout: 5000, maxLimit: 2 * 1024 * 1024 };
    if (body !== undefined) options.extraData = body;
    try {
      const response = await request.request(this.mediaUrl(path), options);
      this.checkActive(token);
      if (redirect) throw new Error('录像机接口不应重定向');
      if (response.responseCode === 404 && path.startsWith('/api/timeline?')) throw new Error('录像机尚不支持全天时间轴，请升级板端服务');
      const rawText = typeof response.result === 'string' ? response.result as string : '';
      let parsed: JsonObject = {};
      try { parsed = parseObject(rawText); } catch (_) {
        if (response.responseCode >= 200 && response.responseCode < 300) throw new Error('接口返回的数据格式无效');
      }
      if (response.responseCode < 200 || response.responseCode >= 300) throw new Error(textValue(parsed['error'], responseError(response.responseCode)));
      return parsed;
    } catch (error) {
      this.checkActive(token);
      if (redirect) throw new Error('录像机接口不应重定向');
      throw error as Error;
    } finally {
      this.requests.delete(request); try { request.destroy(); } catch (_) {}
    }
  }
}
