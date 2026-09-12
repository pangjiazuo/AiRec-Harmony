import { ChannelStatus } from '../model/Models';
import { RecorderState } from './RecorderState';
import { CameraPreview } from './CameraPreview';
import { Palette, Notice, bytesText, metric } from './Theme';

@Component
export struct LivePage {
  @ObjectLink state: RecorderState;
  @Prop bottomInset: number = 0;
  onChannel: (id: number) => void = () => {};
  onDevice: () => void = () => {};
  @State private contentWidth: number = 400;
  private readonly ids: number[] = [1, 2, 3, 4, 5];
  private onlineCount(): number { return this.state.connected ? this.state.status.channels.filter((item: ChannelStatus) => item.state === 'online').length : 0; }
  private recordingCount(): number { return this.state.connected ? this.state.status.channels.filter((item: ChannelStatus) => item.state === 'online' && item.recording).length : 0; }

  @Builder private camera(id: number) {
    Column() {
      CameraPreview({ url: this.state.api().mediaUrl(`/stream/${id}.mjpg`), channelName: this.state.channel(id).name,
        offlineMessage: this.state.previewMessage(id),
        online: this.state.connected && this.state.channel(id).state === 'online',
        active: this.state.foreground && this.state.route === 'live', decodeWidth: 640 })
      Row({ space: 8 }) {
        Row().width(7).height(7).borderRadius(4).backgroundColor(this.state.connected && this.state.channel(id).state === 'online' ? '#39AE83' : '#929AA5');
        Text(this.state.channel(id).name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Palette.text)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
        if (this.state.connected && this.state.channel(id).state === 'online' && this.state.channel(id).recording) {
          Text('REC').fontSize(12).fontColor('#E65B65');
        }
      }.padding(14).width('100%');
    }.backgroundColor(Palette.card).borderRadius(20).clip(true).width('100%')
      .onClick(() => this.onChannel(id)).id(`camera-${id}`).accessibilityText(`打开${this.state.channel(id).name}`);
  }
  build() {
    Scroll() {
      Column({ space: 20 }) {
        Row() {
          Text(`${this.onlineCount()} / 5 路在线`).fontSize(15).fontColor(Palette.secondary).layoutWeight(1);
          Button('设备信息', { type: ButtonType.Normal }).backgroundColor(Color.Transparent).fontColor(Palette.brand)
            .onClick(this.onDevice).id('device-info');
        }.width('100%');
        Row({ space: 20 }) {
          Text(metric(this.state.status.system.temperature_c, '℃')).fontSize(14).fontColor(Palette.text);
          Text(`CPU ${metric(this.state.status.system.cpu_percent, '%')}`).fontSize(14).fontColor(Palette.text);
          Text(`可用 ${bytesText(this.state.status.storage.free_bytes)}`).fontSize(14).fontColor(Palette.text);
        }.width('100%').padding(16).backgroundColor(Palette.card).borderRadius(16).onClick(this.onDevice);
        if (this.state.message) { Notice({ text: this.state.message }); }
        Grid() {
          ForEach(this.ids, (id: number) => { GridItem() { this.camera(id); } }, (id: number) => id.toString());
          GridItem() {
            Column({ space: 12 }) {
              Row() { Text('通道总数').fontColor(Palette.secondary); Blank(); Text('5').fontWeight(FontWeight.Medium).fontColor(Palette.text); }.width('100%');
              Row() { Text('在线通道').fontColor(Palette.secondary); Blank(); Text(this.onlineCount().toString()).fontColor(Palette.text); }.width('100%');
              Row() { Text('正在录像').fontColor(Palette.secondary); Blank(); Text(this.recordingCount().toString()).fontColor(Palette.text); }.width('100%');
              Divider().color(Palette.line);
              Text(this.state.connected ? '设备已连接' : '等待设备连接').fontSize(13).fontColor(Palette.secondary);
            }.padding(16).width('100%').constraintSize({ minHeight: 176 }).backgroundColor(Palette.card).borderRadius(20);
          }
        }.columnsTemplate(this.contentWidth >= 840 ? '1fr 1fr 1fr' : '1fr 1fr').columnsGap(12).rowsGap(16).width('100%');
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 24 + this.bottomInset });
    }.height('100%').width('100%').align(Alignment.Top).scrollBar(BarState.Off).backgroundColor(Palette.background)
      .onAreaChange((_old: Area, area: Area) => { this.contentWidth = Number(area.width); });
  }
}

@Component
export struct DevicePage {
  @ObjectLink state: RecorderState;
  @Builder private item(label: string, value: string) {
    Row() { Text(label).fontSize(15).fontColor(Palette.secondary); Blank(); Text(value).fontSize(15).fontColor(Palette.text).maxLines(2); }
      .width('100%').padding({ top: 15, bottom: 15 });
  }
  build() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.state.message) { Notice({ text: this.state.message }); }
        Column() {
          this.item('设备', this.state.status.system.hostname || '智能录像机'); Divider().color(Palette.line);
          this.item('温度', metric(this.state.status.system.temperature_c, '℃')); Divider().color(Palette.line);
          this.item('CPU', metric(this.state.status.system.cpu_percent, '%')); Divider().color(Palette.line);
          this.item('内存', `${bytesText(this.state.status.system.memory.used_bytes)} / ${bytesText(this.state.status.system.memory.total_bytes)}`); Divider().color(Palette.line);
          this.item('存储可用', bytesText(this.state.status.storage.free_bytes)); Divider().color(Palette.line);
          this.item('存储总量', bytesText(this.state.status.storage.total_bytes)); Divider().color(Palette.line);
          this.item('识别状态', this.state.status.detector.ready ? '已就绪' : '等待识别服务'); Divider().color(Palette.line);
          this.item('运行时间', Number.isFinite(this.state.status.uptime_seconds) ? `${Math.floor(this.state.status.uptime_seconds / 3600)} 小时` : '—');
        }.padding({ left: 20, right: 20 }).backgroundColor(Palette.card).borderRadius(24).width('100%');
      }.padding(16).width('100%').constraintSize({ maxWidth: 840 });
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor(Palette.background);
  }
}
