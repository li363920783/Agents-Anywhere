import { liveViewManager } from '@kit.LiveViewKit';
import { pushService } from '@kit.PushKit';
import { wantAgent, Want, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'AA-LiveView';
const BUNDLE_NAME = 'com.morin.clauderelay';
const ABILITY_NAME = 'EntryAbility';

/**
 * Scenario value. It must match the scenario registered for this app in AGC —
 * a mismatch is reported as 1003500005 "right not enabled", which reads like a
 * missing entitlement but usually just means the string is wrong. Legal values
 * are listed on `LiveView.event`: DELIVERY / FLIGHT / TRAIN / QUEUE / PICK_UP /
 * SCORE / RENT / TIMER / WORKOUT / NAVIGATION / CHECK_IN / EXPRESS / PROGRESS /
 * TRADE.
 */
const EVENT = 'TIMER';

/** 8-digit #AARRGGBB; the SDK rejects 6-digit colours here. */
const ACCENT = '#FF3FB950';
const TRACK = '#333FB950';

/**
 * Progress shown while running. A turn has no measurable completion, so the
 * bar sits near the start rather than creeping towards 100 and reading as
 * "almost done"; only a real finish jumps it.
 */
const PROGRESS_RUNNING = 10;
const PROGRESS_DONE = 100;

/** How long the finished card lingers in the shade, in seconds. */
const KEEP_DONE_S = 5;

/** `sequence` upper bound (SDK range [0, 2147483647]); a stop must exceed any value. */
const STOP_SEQUENCE = 2147483647;

/** Icon names resolve against `resources/rawfile/`. */
const ICON_APP = 'lv_app.png';
const ICON_RUN = 'lv_run.png';

/**
 * 实况窗 for the session that currently needs the user.
 *
 * Huawei grants this per app and validates aggressively — most optional-looking
 * fields are required at runtime, and a wrong scenario string is reported as a
 * missing entitlement. The error codes are translated below because on a device
 * that is the only diagnostic available.
 */
export class LiveView {
  private static enabled: boolean | null = null;
  private static pushToken: string = '';
  private static showing: boolean = false;
  private static title: string = '';
  private static sequence: number = 0;
  /** New per start: a reused id collides with the previous card's archive slot. */
  private static id: number = 0;

  /**
   * Public probe for Settings. Huawei grants 实况窗 per app, so without the
   * entitlement nothing is ever shown and the user needs to know why.
   */
  static async available(): Promise<boolean> {
    return await LiveView.isEnabled();
  }

  /**
   * Push Token. Huawei expects it to be requested at app start, and the device
   * has to be registered with it in AGC's 调测设备管理 before local live-view
   * checks pass — so Settings shows it for copying.
   */
  static token(): string {
    return LiveView.pushToken;
  }

  private static async fetchPushToken(): Promise<void> {
    if (LiveView.pushToken.length > 0) {
      return;
    }
    try {
      const token = await pushService.getToken();
      LiveView.pushToken = token;
      hilog.info(0x0000, TAG, 'push token len=%{public}d', token.length);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'getToken: %{public}s', LiveView.describe(e));
    }
  }

  private static async isEnabled(): Promise<boolean> {
    if (LiveView.enabled === null) {
      try {
        LiveView.enabled = await liveViewManager.isLiveViewEnabled();
      } catch (e) {
        hilog.info(0x0000, TAG, 'live view unavailable: %{public}s', LiveView.describe(e));
        LiveView.enabled = false;
      }
      void LiveView.fetchPushToken();
    }
    return LiveView.enabled;
  }

  /** Starts, or refreshes, the card for `sessionTitle`. */
  static async show(sessionTitle: string, detail: string): Promise<void> {
    if (!await LiveView.isEnabled()) {
      return;
    }
    const switching = !LiveView.showing || LiveView.title !== sessionTitle;
    if (switching) {
      // Clear any orphan first: a card left behind by a killed process still
      // occupies its id, and starting over it fails.
      await LiveView.hide();
      LiveView.id = Date.now() % 2000000000;
      LiveView.sequence = 0;
    }
    try {
      const view = await LiveView.build(sessionTitle, detail, PROGRESS_RUNNING, 0);
      if (switching) {
        LiveView.report('start', await liveViewManager.startLiveView(view));
        LiveView.showing = true;
        LiveView.title = sessionTitle;
      } else {
        LiveView.report('update', await liveViewManager.updateLiveView(view));
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'show: %{public}s', LiveView.describe(e));
    }
  }

  static async hide(): Promise<void> {
    if (!await LiveView.isEnabled() || LiveView.id === 0) {
      return;
    }
    try {
      // `stopLiveView` needs a complete LiveView, and a sequence above whatever
      // the orphan carries — which we cannot know, so use the upper bound.
      const view = await LiveView.build(LiveView.title, '', PROGRESS_DONE, KEEP_DONE_S);
      view.sequence = STOP_SEQUENCE;
      LiveView.report('stop', await liveViewManager.stopLiveView(view));
    } catch (e) {
      hilog.warn(0x0000, TAG, 'hide: %{public}s', LiveView.describe(e));
    } finally {
      LiveView.showing = false;
      LiveView.title = '';
      LiveView.id = 0;
    }
  }

  private static async build(
    sessionTitle: string,
    detail: string,
    progress: number,
    keepTime: number
  ): Promise<liveViewManager.LiveView> {
    LiveView.sequence += 1;
    // Every line carries the same colour: the SDK rejects a payload where the
    // lines disagree, so hierarchy has to come from the text itself.
    const rich: Array<liveViewManager.RichText> = [];
    rich.push({ text: LiveView.clip(sessionTitle, 60), textColor: ACCENT });
    rich.push({ text: LiveView.clip(detail, 60), textColor: ACCENT });

    const capsule: liveViewManager.ProgressCapsule = {
      type: liveViewManager.CapsuleType.CAPSULE_TYPE_PROGRESS,
      status: 1,
      icon: ICON_APP,
      backgroundColor: ACCENT,
      isContentDisplayed: true,
      max: 100,
      progress: progress,
      content: LiveView.clip(sessionTitle, 12)
    };

    const layout: liveViewManager.ProgressLayout = {
      layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PROGRESS,
      progress: progress,
      color: ACCENT,
      backgroundColor: TRACK,
      indicatorType: liveViewManager.IndicatorType.INDICATOR_TYPE_UP,
      indicatorIcon: ICON_RUN,
      lineType: liveViewManager.LineType.LINE_TYPE_THICK_SOLID_LINE,
      nodeIcons: [ICON_APP, ICON_RUN, ICON_RUN]
    };

    const primary: liveViewManager.PrimaryData = {};
    primary.title = 'Agents Anywhere';
    primary.content = rich;
    primary.keepTime = keepTime;
    primary.clickAction = await LiveView.tapAgent();
    primary.layoutData = layout;

    const data: liveViewManager.LiveViewData = { primary: primary };
    data.capsule = capsule;

    const view: liveViewManager.LiveView = {
      id: LiveView.id,
      event: EVENT,
      sequence: LiveView.sequence,
      isMute: true,
      liveViewData: data
    };
    return view;
  }

  private static clip(text: string, max: number): string {
    return text.length > max ? `${text.substring(0, max)}…` : text;
  }

  private static async tapAgent(): Promise<WantAgent> {
    const want: Want = {
      bundleName: BUNDLE_NAME,
      abilityName: ABILITY_NAME
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [want],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return await wantAgent.getWantAgent(info);
  }

  /** The API reports failures in the result rather than by throwing. */
  private static report(action: string, result: liveViewManager.LiveViewResult): void {
    if (result.resultCode === 0) {
      hilog.info(0x0000, TAG, '%{public}s ok', action);
    } else {
      hilog.warn(0x0000, TAG, '%{public}s failed: %{public}s',
        action, LiveView.explain(result.resultCode, `${result.message}`));
    }
  }

  /**
   * Turns a LiveView error into something actionable. `BusinessError.message`
   * is non-enumerable, so it has to be read explicitly — the parameter errors
   * are only diagnosable through that string.
   */
  private static describe(e: Object): string {
    const err = e as BusinessError;
    const code: number = err.code === undefined ? 0 : err.code;
    // `BusinessError.message` is a boxed String, not a primitive.
    return LiveView.explain(code, `${err.message}`);
  }

  private static explain(code: number, message: string): string {
    if (code === 1003500004) {
      return `实况窗未启用（${code}）：系统侧没开这个能力。`;
    }
    if (code === 1003500005) {
      return `报「权益未开通」（${code}），但更常见的是场景值对不上：`
        + `代码里是 ${EVENT}，需要和 AGC 开通实况窗时选的场景一致。`;
    }
    if (code === 1003500006) {
      return `同 id 的实况窗已存在（${code}）：先 stop 再 start。`;
    }
    if (code === 1003500008) {
      return `创建频率超限（${code}）：刷新太频繁。`;
    }
    if (code === 1003500010) {
      return `实况窗已结束（${code}）：需要重新 start。`;
    }
    if (code === 1003500011) {
      return `sequence 没有递增（${code}）。`;
    }
    return `${code} ${message}`;
  }
}
