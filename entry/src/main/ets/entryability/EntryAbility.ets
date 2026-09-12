import { UIAbility, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    AppStorage.setOrCreate('recorderForeground', true);
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }
  onWindowStageCreate(stage: window.WindowStage): void {
    stage.getMainWindow().then((main: window.Window) => main.setPreferredOrientation(window.Orientation.AUTO_ROTATION))
      .catch((error: Error) => hilog.warn(0x0100, 'Recorder', '设置旋转方向失败：%{public}s', error.message));
    stage.loadContent('pages/Index').catch((error: Error) => hilog.error(0x0100, 'Recorder', '加载主页面失败：%{public}s', error.message));
  }
  onForeground(): void { AppStorage.setOrCreate('recorderForeground', true); }
  onBackground(): void { AppStorage.setOrCreate('recorderForeground', false); }
}
