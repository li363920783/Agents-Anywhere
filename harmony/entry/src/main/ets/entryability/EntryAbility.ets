import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppState } from '../core/AppState';
import { Prefs } from '../core/store/Prefs';
import { KeepAlive } from '../core/notify/KeepAlive';
import { DashboardWatcher } from '../core/net/DashboardWatcher';
import { Notifier, WANT_SESSION_KEY } from '../core/notify/Notifier';

/** AppStorage key the Index page watches to open a session from a notification tap. */
export const OPEN_SESSION_KEY = 'aa_open_session';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Prefs.init(this.context);
    KeepAlive.attach(this.context);
    Notifier.attach(this.context);
    this.routeFromWant(want);
    hilog.info(0x0000, 'AgentsAnywhere', 'ability onCreate');
    void AppState.shared.restore().then(() => {
      hilog.info(0x0000, 'AgentsAnywhere', `restore done, signedIn=${AppState.shared.signedIn}`);
      if (AppState.shared.signedIn) {
        DashboardWatcher.shared.start();
      }
    });
  }

  /** A notification tap while the app is already running arrives here. */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.routeFromWant(want);
  }

  onForeground(): void {
    // The tray alert for the session the user is now reading is stale.
    const open = AppStorage.get<string>(OPEN_SESSION_KEY);
    if (open !== undefined && open.length > 0) {
      void Notifier.clear(open);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err) {
        hilog.error(0x0000, 'AgentsAnywhere', 'loadContent failed: %{public}s', err.message);
      }
    });
  }

  onDestroy(): void {
    DashboardWatcher.shared.stop();
  }

  /** A notification tap carries the session id; publish it as a route request. */
  private routeFromWant(want: Want): void {
    const params = want.parameters;
    if (params === undefined) {
      return;
    }
    const id = params[WANT_SESSION_KEY];
    if (typeof id === 'string' && id.length > 0) {
      AppStorage.setOrCreate(OPEN_SESSION_KEY, id);
    }
  }
}
