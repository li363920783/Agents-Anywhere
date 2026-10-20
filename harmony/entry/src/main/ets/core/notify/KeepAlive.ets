import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent, Want, WantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'AA-KeepAlive';
const BUNDLE_NAME = 'com.morin.agentsanywhere';
const ABILITY_NAME = 'EntryAbility';

/**
 * Holds a `dataTransfer` continuous task while a turn is in flight so the
 * dashboard socket — and therefore the notifications — survive the app going to
 * the background.
 *
 * Deliberately not always-on: a permanent continuous task pins a notification
 * in the tray and drains the battery, and the only thing worth staying awake
 * for is a running turn.
 */
export class KeepAlive {
  private static running: boolean = false;
  private static busy: boolean = false;
  private static context: common.UIAbilityContext | null = null;

  /** The ability context is required to start a continuous task. */
  static attach(context: common.UIAbilityContext): void {
    KeepAlive.context = context;
  }

  /** Idempotent: callers pass whether anything is currently running. */
  static sync(shouldRun: boolean): void {
    if (KeepAlive.busy || shouldRun === KeepAlive.running) {
      return;
    }
    void KeepAlive.apply(shouldRun);
  }

  static get active(): boolean {
    return KeepAlive.running;
  }

  private static async apply(shouldRun: boolean): Promise<void> {
    const ctx = KeepAlive.context;
    if (ctx === null) {
      return;
    }
    KeepAlive.busy = true;
    try {
      if (shouldRun) {
        await backgroundTaskManager.startBackgroundRunning(
          ctx,
          backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
          await KeepAlive.tapAgent()
        );
        KeepAlive.running = true;
      } else {
        await backgroundTaskManager.stopBackgroundRunning(ctx);
        KeepAlive.running = false;
      }
    } catch (e) {
      // Emulators and unprivileged builds reject this; notifications then only
      // fire while the app is in the foreground.
      hilog.warn(0x0000, TAG, 'continuous task: %{public}s', (e as Error).message);
    } finally {
      KeepAlive.busy = false;
    }
  }

  private static async tapAgent(): Promise<WantAgent> {
    const want: Want = {
      bundleName: BUNDLE_NAME,
      abilityName: ABILITY_NAME
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [want],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 1
    };
    return await wantAgent.getWantAgent(info);
  }
}
