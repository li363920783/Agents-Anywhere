import { liveViewManager } from '@kit.LiveViewKit';
import { wantAgent, Want, WantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'AA-LiveView';
const BUNDLE_NAME = 'com.morin.agentsanywhere';
const ABILITY_NAME = 'EntryAbility';
/** One live view at a time: it shows the turn that is currently running. */
const LIVE_ID = 20261020;
const EVENT = 'AGENT_TURN';

/**
 * 实况窗 for the running turn — lock screen / status bar progress without
 * opening the app.
 *
 * Huawei gates this behind a per-app entitlement. Without it
 * `isLiveViewEnabled()` returns false and every call here is a silent no-op,
 * which is the intended behaviour: the feature is an enhancement, never a
 * dependency of the main flow.
 */
export class LiveView {
  private static enabled: boolean | null = null;
  private static showing: boolean = false;
  private static title: string = '';

  /**
   * Public probe for Settings. Huawei grants 实况窗 per app, so without the
   * entitlement nothing is ever shown and the user needs to know why.
   */
  static async available(): Promise<boolean> {
    return await LiveView.isEnabled();
  }

  private static async isEnabled(): Promise<boolean> {
    if (LiveView.enabled === null) {
      try {
        LiveView.enabled = await liveViewManager.isLiveViewEnabled();
      } catch (e) {
        hilog.info(0x0000, TAG, 'live view unavailable: %{public}s', (e as Error).message);
        LiveView.enabled = false;
      }
    }
    return LiveView.enabled;
  }

  /** Starts (or refreshes) the card for `sessionTitle`. */
  static async show(sessionTitle: string, detail: string): Promise<void> {
    if (!await LiveView.isEnabled()) {
      return;
    }
    try {
      const view = await LiveView.build(sessionTitle, detail);
      if (LiveView.showing && LiveView.title === sessionTitle) {
        await liveViewManager.updateLiveView(view);
      } else {
        await liveViewManager.startLiveView(view);
        LiveView.showing = true;
        LiveView.title = sessionTitle;
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'show: %{public}s', (e as Error).message);
    }
  }

  static async hide(): Promise<void> {
    if (!LiveView.showing || !await LiveView.isEnabled()) {
      return;
    }
    try {
      await liveViewManager.stopLiveView(await LiveView.build(LiveView.title, ''));
    } catch (e) {
      hilog.warn(0x0000, TAG, 'hide: %{public}s', (e as Error).message);
    } finally {
      LiveView.showing = false;
      LiveView.title = '';
    }
  }

  private static async build(sessionTitle: string, detail: string): Promise<liveViewManager.LiveView> {
    const rich: liveViewManager.RichText = { text: detail };
    // A turn has no measurable progress, so the capsule spins instead of
    // reporting a percentage the server cannot supply.
    const capsule: liveViewManager.ProgressCapsule = {
      type: liveViewManager.CapsuleType.CAPSULE_TYPE_PROGRESS,
      status: 1,
      indeterminate: true,
      content: '运行中'
    };

    const primary: liveViewManager.PrimaryData = {};
    primary.title = sessionTitle;
    primary.content = [rich];
    primary.clickAction = await LiveView.tapAgent();

    const data: liveViewManager.LiveViewData = { primary: primary };
    data.capsule = capsule;

    const view: liveViewManager.LiveView = {
      id: LIVE_ID,
      event: EVENT,
      liveViewData: data
    };
    return view;
  }

  private static async tapAgent(): Promise<WantAgent> {
    const want: Want = {
      bundleName: BUNDLE_NAME,
      abilityName: ABILITY_NAME
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [want],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: LIVE_ID
    };
    return await wantAgent.getWantAgent(info);
  }
}
