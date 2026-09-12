import { image } from '@kit.ImageKit';
import { MjpegStream } from '../media/MjpegStream';
import { Palette } from './Theme';

/** 每路独立连接和解码，只保留最新等待帧，避免慢设备积压图片。 */
@Component
export struct CameraPreview {
  @Prop @Watch('connectionChanged') url: string = '';
  @Prop @Watch('connectionChanged') active: boolean = false;
  @Prop @Watch('connectionChanged') online: boolean = false;
  @Prop channelName: string = '';
  @Prop offlineMessage: string = '暂无信号';
  decodeWidth: number = 640;
  @State private frame: image.PixelMap | undefined = undefined;
  @State private message: string = '正在连接画面…';
  private stream: MjpegStream = new MjpegStream();
  private generation: number = 0;
  private decoding: boolean = false;
  private pending: ArrayBuffer | undefined = undefined;
  private retained: image.PixelMap[] = [];
  private mounted: boolean = false;

  aboutToAppear(): void { this.mounted = true; this.connectionChanged(); }
  aboutToDisappear(): void { this.mounted = false; this.stop(); }
  private stop(): void {
    this.generation++; this.stream.stop(); this.pending = undefined; this.frame = undefined;
    this.retained.forEach((item: image.PixelMap) => { item.release(); }); this.retained = [];
  }
  private connectionChanged(): void {
    this.stop();
    if (!this.mounted || !this.active || !this.online || this.url.length === 0) return;
    this.message = '正在连接画面…';
    const generation = this.generation;
    this.stream.start(this.url, (jpeg: ArrayBuffer) => {
      if (generation !== this.generation) return;
      this.pending = jpeg;
      if (!this.decoding) this.decode(generation);
    }, (message: string) => { if (generation === this.generation) this.message = message; });
  }
  private async decode(generation: number): Promise<void> {
    this.decoding = true;
    try {
      while (generation === this.generation && this.pending !== undefined) {
        const data = this.pending; this.pending = undefined;
        const source = image.createImageSource(data);
        try {
          const pixel = await source.createPixelMap({ desiredSize: { width: this.decodeWidth, height: Math.round(this.decodeWidth * 9 / 16) } });
          if (generation !== this.generation) { pixel.release(); break; }
          this.frame = pixel; this.message = '';
          this.retained.push(pixel);
          // 留出已提交帧的渲染时间，随后释放旧的原生图像内存。
          if (this.retained.length > 3) this.retained.shift()?.release();
        } finally { source.release(); }
      }
    } catch (error) {
      if (generation === this.generation) this.message = '画面正在恢复…';
    } finally {
      this.decoding = false;
      if (this.pending !== undefined && this.mounted && this.active && this.online) this.decode(this.generation);
    }
  }
  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.frame !== undefined && this.active && this.online) {
        Image(this.frame).width('100%').height('100%').objectFit(ImageFit.Contain)
          .accessibilityText(`${this.channelName}实时画面`).id(`preview-${this.channelName}`);
        if (this.message) {
          Text('画面中断 · 正在恢复').fontSize(12).fontColor('#FFFFFF').padding(6)
            .width('100%').backgroundColor('#B3111318').align(Alignment.Bottom);
        }
      } else {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.video')).fontSize(32).fontColor([Palette.secondary]);
          Text(!this.online ? this.offlineMessage : (!this.active ? '预览已暂停' : this.message))
            .fontSize(13).fontColor(Palette.secondary);
        }
      }
    }.width('100%').aspectRatio(16 / 9).backgroundColor(this.online ? '#111318' : Palette.preview);
  }
}
