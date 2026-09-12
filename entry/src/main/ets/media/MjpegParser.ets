/** 按每个 multipart 片段的 Content-Length 拆帧，内存始终有上限。 */
export class MjpegParser {
  private pending: Uint8Array = new Uint8Array(0);
  private wanted: number = 0;
  private readonly maxFrame: number = 4 * 1024 * 1024;
  private readonly maxHeader: number = 8192;
  private onFrame: (jpeg: ArrayBuffer) => void;
  constructor(onFrame: (jpeg: ArrayBuffer) => void) { this.onFrame = onFrame; }
  reset(): void { this.pending = new Uint8Array(0); this.wanted = 0; }
  feed(chunk: ArrayBuffer): void {
    if (this.pending.length + chunk.byteLength > this.maxFrame + this.maxHeader) throw new Error('预览帧超过大小限制');
    const combined = new Uint8Array(this.pending.length + chunk.byteLength);
    combined.set(this.pending); combined.set(new Uint8Array(chunk), this.pending.length); this.pending = combined;
    while (this.pending.length > 0) {
      if (this.wanted === 0) {
        let end = -1;
        for (let i = 0; i + 3 < this.pending.length; i++) {
          if (this.pending[i] === 13 && this.pending[i + 1] === 10 && this.pending[i + 2] === 13 && this.pending[i + 3] === 10) { end = i; break; }
        }
        if (end < 0) { if (this.pending.length > this.maxHeader) throw new Error('预览片段头部过大'); return; }
        if (end > this.maxHeader) throw new Error('预览片段头部过大');
        let header = '';
        for (let i = 0; i < end; i++) header += String.fromCharCode(this.pending[i]);
        const match = /(?:^|\r\n)Content-Length:\s*(\d+)\s*(?:\r\n|$)/i.exec(header);
        this.wanted = match ? Number(match[1]) : 0;
        if (!Number.isInteger(this.wanted) || this.wanted < 4 || this.wanted > this.maxFrame) throw new Error('预览片段长度无效');
        this.pending = this.pending.slice(end + 4);
      }
      if (this.pending.length < this.wanted) return;
      const jpeg = this.pending.slice(0, this.wanted);
      this.pending = this.pending.slice(this.wanted); this.wanted = 0;
      if (jpeg[0] !== 255 || jpeg[1] !== 216 || jpeg[jpeg.length - 2] !== 255 || jpeg[jpeg.length - 1] !== 217) throw new Error('预览 JPEG 不完整');
      this.onFrame(jpeg.buffer as ArrayBuffer);
    }
  }
}
