import { http } from '@kit.NetworkKit';
import { headerText, headerStatus, responseError } from '../data/RecorderApi';
import { MjpegParser } from './MjpegParser';

/** 每一路拥有自己的请求、超时与重试；无信号不会阻塞其他通道。 */
export class MjpegStream {
  private request?: http.HttpRequest;
  private retryTimer: number = 0;
  private watchdog: number = 0;
  private generation: number = 0;
  private retry: number = 0;
  private address: string = '';
  private onFrame: (jpeg: ArrayBuffer) => void = (_: ArrayBuffer): void => {};
  private onState: (message: string) => void = (_: string): void => {};
  private message: string = '';

  start(address: string, onFrame: (jpeg: ArrayBuffer) => void, onState: (message: string) => void): void {
    this.stop(); this.address = address; this.onFrame = onFrame; this.onState = onState; this.retry = 0;
    this.connect(this.generation);
  }
  stop(): void {
    this.generation++;
    if (this.retryTimer) clearTimeout(this.retryTimer); this.retryTimer = 0;
    if (this.watchdog) clearInterval(this.watchdog); this.watchdog = 0;
    const request = this.request; this.request = undefined;
    if (request) { try { request.destroy(); } catch (_) {} }
  }
  private state(value: string): void { if (value !== this.message) { this.message = value; this.onState(value); } }
  private connect(generation: number): void {
    if (generation !== this.generation) return;
    this.state('正在连接画面…');
    const request = http.createHttp(); this.request = request;
    let lastFrame = Date.now();
    let approved = false;
    const parser = new MjpegParser((jpeg: ArrayBuffer): void => {
      if (generation !== this.generation || this.request !== request) return;
      lastFrame = Date.now(); this.retry = 0; this.state(''); this.onFrame(jpeg);
    });
    const finish = (message: string): void => {
      if (generation !== this.generation || this.request !== request) return;
      this.request = undefined; try { request.destroy(); } catch (_) {} parser.reset();
      if (this.watchdog) clearInterval(this.watchdog); this.watchdog = 0;
      this.state(`${message}，自动重连中`);
      const wait = Math.min(1000 * Math.pow(2, this.retry++), 10000);
      this.retryTimer = setTimeout((): void => { this.retryTimer = 0; this.connect(generation); }, wait);
    };
    request.on('headersReceive', (headers: Object): void => {
      const status = headerStatus(headers);
      if (status >= 300) { finish(responseError(status)); return; }
      approved = headerText(headers, 'content-type').toLowerCase().startsWith('multipart/');
      if (!approved) finish('不是有效的 MJPEG 预览');
    });
    request.on('dataReceive', (chunk: ArrayBuffer): void => {
      if (!approved || generation !== this.generation || this.request !== request) return;
      try { parser.feed(chunk); } catch (error) { finish((error as Error).message); }
    });
    request.on('dataEnd', (): void => finish('预览连接已结束'));
    this.watchdog = setInterval((): void => { if (Date.now() - lastFrame > 12000) finish('预览响应超时'); }, 2000);
    const headers: Record<string, string> = { 'Accept': 'multipart/x-mixed-replace' };
    const options: http.HttpRequestOptions = { method: http.RequestMethod.GET, usingCache: false, usingProxy: false,
      connectTimeout: 5000, readTimeout: 0, header: headers };
    try {
      request.requestInStream(this.address, options).then((code: number): void => finish(code >= 300 ? responseError(code) : '预览连接已结束'))
        .catch((error: Error): void => finish(error.message || '预览连接失败'));
    } catch (error) { finish((error as Error).message || '预览连接失败'); }
  }
}
