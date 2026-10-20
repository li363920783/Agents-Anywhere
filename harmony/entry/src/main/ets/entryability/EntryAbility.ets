import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppState } from '../core/AppState';
import { Prefs } from '../core/store/Prefs';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Prefs.init(this.context);
    hilog.info(0x0000, 'AgentsAnywhere', 'ability onCreate');
    void AppState.shared.restore().then(() => {
      hilog.info(0x0000, 'AgentsAnywhere', `restore done, signedIn=${AppState.shared.signedIn}`);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err) {
        hilog.error(0x0000, 'AgentsAnywhere', 'loadContent failed: %{public}s', err.message);
      }
    });
  }
}
