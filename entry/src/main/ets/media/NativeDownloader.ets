import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { DownloadResult } from '../model/Models';
import { headerStatus, headerText, responseError } from '../data/RecorderApi';

export type DownloadKind = 'logs' | 'recording';

/** 网络数据流式落盘，完成后再交给系统保存选择器，失败不留下损坏的用户录像。 */
export class NativeDownloader {
  private busy: boolean = false;
  private generation: number = 0;
  private abort?: () => void;

  cancel(): void { this.generation++; if (this.abort) this.abort(); }
  async save(context: common.UIAbilityContext, address: string, kind: DownloadKind, filename: string,
    onProgress: (bytes: number) => void = (_: number): void => {}): Promise<DownloadResult> {
    if (this.busy) throw new Error('已有下载任务正在进行');
    this.busy = true;
    const token = ++this.generation;
    const maximum = kind === 'logs' ? 16 * 1024 * 1024 : 2 * 1024 * 1024 * 1024;
    let temporary = '';
    let source: fileIo.File | undefined = undefined;
    let target: fileIo.File | undefined = undefined;
    let targetWasEmpty = false;
    let targetFinished = false;
    // 进度属于界面通知；页面退出等通知异常不能使网络 Promise 悬挂。
    const progress = (bytes: number): void => { try { onProgress(bytes); } catch (_) {} };
    try {
      temporary = `${context.cacheDir}/recorder-download-${util.generateRandomUUID()}.part`;
      source = fileIo.openSync(temporary, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      progress(0);
      if (token !== this.generation) throw new Error('下载已取消');
      const bytes = await this.receiveToFile(address, source.fd, maximum, kind, progress);
      fileIo.closeSync(source); source = undefined;
      if (token !== this.generation) throw new Error('下载已取消');
      const suffix = kind === 'logs' ? '.zip' : '.mp4';
      let name = filename.replace(/[\\/:*?"<>|\x00-\x1F]/g, '-').slice(0, 100);
      if (!name) name = `smart-recorder-${Date.now()}`;
      if (!name.toLowerCase().endsWith(suffix)) name += suffix;
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [name]; options.fileSuffixChoices = [kind === 'logs' ? '诊断日志|.zip' : '录像片段|.mp4'];
      const destinations = await new picker.DocumentViewPicker(context).save(options);
      if (destinations.length === 0 || token !== this.generation) return { saved: false, uri: '', bytes: 0 };
      target = fileIo.openSync(destinations[0], fileIo.OpenMode.READ_WRITE);
      targetWasEmpty = fileIo.statSync(target.fd).size === 0;
      // 原生文件复制不会将整个 MP4 读入 ArkTS 内存。
      await fileIo.copyFile(temporary, target.fd);
      if (token !== this.generation) throw new Error('下载已取消');
      if (fileIo.statSync(target.fd).size !== bytes) throw new Error('保存后的文件大小不匹配');
      targetFinished = true;
      return { saved: true, uri: destinations[0], bytes: bytes };
    } finally {
      this.abort = undefined;
      if (source) { try { fileIo.closeSync(source); } catch (_) {} }
      if (target) {
        // 保存阶段异常时清空本次新建目标的部分内容，不删除用户已有文件。
        if (!targetFinished && targetWasEmpty) { try { fileIo.truncateSync(target.fd, 0); } catch (_) {} }
        try { fileIo.closeSync(target); } catch (_) {}
      }
      try { if (temporary && fileIo.accessSync(temporary)) fileIo.unlinkSync(temporary); } catch (_) {}
      this.busy = false;
    }
  }

  private receiveToFile(address: string, fd: number, maximum: number, kind: DownloadKind,
    onProgress: (bytes: number) => void): Promise<number> {
    return new Promise<number>((resolve, reject): void => {
      const request = http.createHttp();
      let finished = false; let ended = false; let requestDone = false; let status = 0; let count = 0; let expected = -1;
      let approved = false; let lastData = Date.now(); let lastProgress = 0;
      let watchdog = 0;
      const close = (): void => {
        if (watchdog) clearInterval(watchdog);
        try { request.destroy(); } catch (_) {} this.abort = undefined;
      };
      const fail = (message: string): void => {
        if (finished) return; finished = true; close(); reject(new Error(message));
      };
      const complete = (): void => {
        if (finished || !ended || !requestDone || status === 0) return;
        if (status < 200 || status >= 300) { fail(responseError(status)); return; }
        if (count === 0 || (expected >= 0 && count !== expected)) { fail('下载文件不完整，请重试'); return; }
        finished = true; close(); onProgress(count); resolve(count);
      };
      this.abort = (): void => fail('下载已取消');
      request.on('headersReceive', (headers: Object): void => {
        if (finished) return;
        status = headerStatus(headers);
        if (status >= 300) { fail(responseError(status)); return; }
        const length = headerText(headers, 'content-length');
        expected = length && /^\d+$/.test(length) ? Number(length) : -1;
        if (expected > maximum) { fail('下载文件超过大小限制'); return; }
        const content = headerText(headers, 'content-type').toLowerCase();
        approved = kind === 'logs' ? content.includes('application/zip') || content.includes('application/octet-stream') :
          content.includes('video/mp4') || content.includes('application/octet-stream');
        if (!approved) fail('响应不是所需的 ZIP 或 MP4 文件');
      });
      request.on('dataReceive', (chunk: ArrayBuffer): void => {
        if (finished || !approved) return;
        if (count + chunk.byteLength > maximum) { fail('下载文件超过大小限制'); return; }
        try {
          let offset = 0;
          while (offset < chunk.byteLength) {
            const end = Math.min(offset + 64 * 1024, chunk.byteLength);
            const block = chunk.slice(offset, end);
            const written = fileIo.writeSync(fd, block);
            if (written <= 0) throw new Error('无法写入下载文件');
            offset += written; count += written;
          }
          lastData = Date.now();
          if (lastData - lastProgress > 250) { lastProgress = lastData; onProgress(count); }
        } catch (error) { fail((error as Error).message); }
      });
      request.on('dataEnd', (): void => { ended = true; complete(); });
      watchdog = setInterval((): void => { if (Date.now() - lastData > 15000) fail('下载响应超时，请重试'); }, 2000);
      const headers: Record<string, string> = { 'Accept': kind === 'logs' ? 'application/zip' : 'video/mp4' };
      const options: http.HttpRequestOptions = { method: http.RequestMethod.GET, usingCache: false, usingProxy: false,
        connectTimeout: 5000, readTimeout: 0, header: headers };
      try {
        request.requestInStream(address, options).then((code: number): void => { status = code; requestDone = true; complete(); })
          .catch((error: Error): void => fail(error.message || '下载连接失败'));
      } catch (error) { fail((error as Error).message || '下载连接失败'); }
    });
  }
}
