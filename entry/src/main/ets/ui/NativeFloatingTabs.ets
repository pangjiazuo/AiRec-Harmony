import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 此文件仅在 API 23 起按需加载，旧系统不会提前加载新的材质模块。
@Component
export struct NativeFloatingTabs {
  @Prop selectedIndex: number = 0;
  @BuilderParam content: () => void;
  onSelect: (index: number) => void = () => {};
  private controller: HdsTabsController = new HdsTabsController();

  aboutToAppear(): void {
    if (deviceInfo.sdkApiVersion >= 23) {
      try {
        // 仅记录系统支持能力，不把它当作当前画面的实际材质等级。
        hilog.info(0x3900, 'RecorderUI', 'HDS dock: API=%{public}d, supportedMaterials=%{public}s, adaptive=true',
          deviceInfo.sdkApiVersion, JSON.stringify(hdsMaterial.getSystemMaterialTypes()));
      } catch (error) {
        hilog.warn(0x3900, 'RecorderUI', 'Unable to query material capability; using system adaptive style');
      }
    }
  }

  build() {
    if (deviceInfo.sdkApiVersion >= 23) {
      HdsTabs({ index: this.selectedIndex, controller: this.controller,
        barPosition: BarPosition.End }) {
        this.content();
      }
      .barPosition(BarPosition.End)
      .vertical(false)
      .barOverlap(true)
      // 宽屏也保留官方浮栏，由组件按断点布局；不覆盖其宽高与圆角。
      .barFloatingStyle({
        barSideMargin: 16,
        barBottomMargin: 12,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        thermoCtrl: true
      })
      .scrollable(false)
      .animationDuration(180)
      .onChange((index: number) => this.onSelect(index))
      .width('100%').height('100%');
    }
  }
}
