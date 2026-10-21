import { liveViewManager } from '@kit.LiveViewKit';
import { pushService } from '@kit.PushKit';
import { wantAgent, Want, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WANT_SESSION_KEY } from './Notifier';
import { Prefs } from '../store/Prefs';

const TAG = 'AA-LiveView';
const BUNDLE_NAME = 'com.morin.clauderelay';
const ABILITY_NAME = 'EntryAbility';

/** Title for a stop payload; the SDK rejects an empty one. */
const FALLBACK_TITLE = 'Agents Anywhere';

/**
 * Scenario value. It must match the scenario registered for this app in AGC —
 * a mismatch is reported as 1003500005 "right not enabled", which reads like a
 * missing entitlement but usually just means the string is wrong. Legal values
 * are listed on `LiveView.event`: DELIVERY / FLIGHT / TRAIN / QUEUE / PICK_UP /
 * SCORE / RENT / TIMER / WORKOUT / NAVIGATION / CHECK_IN / EXPRESS / PROGRESS /
 * TRADE.
 */
const EVENT = 'TIMER';

/** 8-digit #AARRGGBB; the SDK rejects 6-digit colours here. Brand blue, so the
 *  card matches the app's accent instead of standing out as a foreign green. */
const ACCENT = '#FF007DFF';
const TRACK = '#33007DFF';

/**
 * Progress shown while running. A turn has no measurable completion, so the bar
 * eases towards a ceiling and never reaches it — a bar that creeps to 90% reads
 * as "almost done" while the agent may have just started.
 */
const PROGRESS_START = 8;
const PROGRESS_CEILING = 70;
/** Half-way point of the easing curve, in minutes. */
const PROGRESS_HALF_LIFE_MIN = 5;
const PROGRESS_DONE = 100;

/** How long the finished card lingers in the shade, in seconds. */
const KEEP_DONE_S = 5;

/** `sequence` upper bound (SDK range [0, 2147483647]); a stop must exceed any value. */
const STOP_SEQUENCE = 2147483647;

/** Icon names resolve against `resources/rawfile/`. */
const ICON_APP = 'lv_app.png';
const ICON_RUN = 'lv_run.png';
const ICON_DONE = 'lv_done.png';
/** Lock-screen immersive picture, revealed when the capsule is pressed. */
const LOCK_PICTURE = 'lv_backdrop.png';

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
  /** Session the card points at; burned into the tap intent. */
  private static sessionId: string = '';
  private static sequence: number = 0;
  /** New per start: a reused id collides with the previous card's archive slot. */
  private static id: number = 0;
  private static loaded: boolean = false;

  /**
   * Restores the card id from a previous process. Without this `hide` cannot
   * reach an orphan — the id only ever lived in the dead process's memory — so
   * the card is never stopped and every later run starts yet another one.
   * That is the whole reason cards piled up in the shade.
   */
  private static load(): void {
    if (LiveView.loaded) {
      return;
    }
    LiveView.loaded = true;
    LiveView.id = Prefs.getNumber(Prefs.keys.liveViewId, 0);
    LiveView.showing = Prefs.getBool(Prefs.keys.liveViewLive, false);
  }

  /** Drops the local record; the card is gone or beyond reach either way. */
  private static forget(): void {
    LiveView.showing = false;
    LiveView.title = '';
    LiveView.id = 0;
    Prefs.putBool(Prefs.keys.liveViewLive, false);
  }

  /**
   * Stops a card left behind by a process that died while it was showing.
   * Called once at launch, before any new card can be started.
   */
  static async reap(): Promise<void> {
    LiveView.load();
    if (!LiveView.showing || LiveView.id === 0) {
      return;
    }
    hilog.info(0x0000, TAG, 'reaping orphan live view id=%{public}d', LiveView.id);
    if (await LiveView.isEnabled()) {
      try {
        await LiveView.stopCard();
      } catch (e) {
        hilog.warn(0x0000, TAG, 'reap: %{public}s', LiveView.describe(e));
      }
    }
    LiveView.forget();
  }

  /**
   * Public probe for Settings. Huawei grants 实况窗 per app, so without the
   * entitlement nothing is ever shown and the user needs to know why.
   */
  static async available(): Promise<boolean> {
    return await LiveView.isEnabled();
  }

  /**
   * Soft progress for a turn of unknown length: eases from START towards the
   * ceiling with a five-minute half-life, so the bar moves early and then
   * settles instead of racing to 100 while the agent is still working.
   */
  static progressFor(elapsedMs: number): number {
    const minutes = Math.max(0, elapsedMs) / 60000;
    const span = PROGRESS_CEILING - PROGRESS_START;
    const eased = 1 - Math.exp(-minutes / PROGRESS_HALF_LIFE_MIN);
    return Math.round(PROGRESS_START + span * eased);
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
  static async show(
    sessionId: string,
    sessionTitle: string,
    detail: string,
    progress: number
  ): Promise<void> {
    LiveView.load();
    if (!await LiveView.isEnabled()) {
      return;
    }
    LiveView.sessionId = sessionId;
    const switching = !LiveView.showing || LiveView.title !== sessionTitle;
    if (switching) {
      // Clear the current card first: it still occupies its id, and starting
      // over it fails.
      await LiveView.hide();
      LiveView.id = Date.now() % 2000000000;
      LiveView.sequence = 0;
      LiveView.sessionId = sessionId;
      // Recorded *before* the start call, so a process that dies mid-start
      // still leaves an id behind for the next launch to reap.
      Prefs.putNumber(Prefs.keys.liveViewId, LiveView.id);
      Prefs.putBool(Prefs.keys.liveViewLive, true);
    }
    try {
      const view = await LiveView.build(sessionTitle, detail, progress, 0);
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
    LiveView.load();
    if (!LiveView.showing || LiveView.id === 0) {
      return;
    }
    if (await LiveView.isEnabled()) {
      try {
        await LiveView.stopCard();
      } catch (e) {
        hilog.warn(0x0000, TAG, 'hide: %{public}s', LiveView.describe(e));
      }
    }
    // Cleared even when the stop failed: an id we cannot reach must not pin the
    // flag, or every launch would reap a card that is already gone.
    LiveView.forget();
  }

  /** Ends the current card. The id survives a restart, so this always reaches it. */
  private static async stopCard(): Promise<void> {
    const title = LiveView.title.length > 0 ? LiveView.title : FALLBACK_TITLE;
    const view = await LiveView.build(title, '', PROGRESS_DONE, KEEP_DONE_S);
    view.sequence = STOP_SEQUENCE;
    LiveView.report('stop', await liveViewManager.stopLiveView(view));
  }

  private static async build(
    sessionTitle: string,
    detail: string,
    progress: number,
    keepTime: number
  ): Promise<liveViewManager.LiveView> {
    LiveView.sequence += 1;
    // No `textColor`: the system default adapts to light and dark and stays
    // legible on the card's glass. A fixed green did not, and the SDK rejects a
    // payload whose lines disagree, so setting one meant setting all of them.
    const rich: Array<liveViewManager.RichText> = [];
    rich.push({ text: LiveView.clip(sessionTitle, 60) });
    rich.push({ text: LiveView.clip(detail, 60) });

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
      nodeIcons: [ICON_APP, ICON_RUN, ICON_DONE]
    };

    const primary: liveViewManager.PrimaryData = {};
    primary.title = 'Agents Anywhere';
    primary.content = rich;
    primary.keepTime = keepTime;
    primary.clickAction = await LiveView.tapAgent();
    primary.layoutData = layout;
    primary.liveViewLockScreenPicture = LOCK_PICTURE;

    const data: liveViewManager.LiveViewData = { primary: primary };
    data.capsule = capsule;

    const view: liveViewManager.LiveView = {
      id: LiveView.id,
      event: EVENT,
      sequence: LiveView.sequence,
      isMute: true,
      // The default (STOP_BY_APP) lets the card outlive the process that made
      // it. Its id only ever existed in that process, so once the process is
      // gone nothing can stop it — which is exactly how cards piled up in the
      // shade. This app owns the whole lifecycle, so the system should end the
      // card along with the process.
      lifeCycleMode: liveViewManager.LifeCycleMode.AUTO_STOP_WHEN_APP_TERMINATE,
      liveViewData: data
    };
    return view;
  }

  private static clip(text: string, max: number): string {
    return text.length > max ? `${text.substring(0, max)}…` : text;
  }

  private static async tapAgent(): Promise<WantAgent> {
    // The session id has to travel with the intent: without it, tapping the
    // card only raises the app on whatever session was last open.
    const params: Record<string, Object> = {};
    params[WANT_SESSION_KEY] = LiveView.sessionId;
    const want: Want = {
      bundleName: BUNDLE_NAME,
      abilityName: ABILITY_NAME,
      parameters: params
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
    if (code === 1) {
      // A `LiveViewResult.resultCode`, not a BusinessError code. Seen when
      // stopping a card whose owning process is gone.
      return '实况窗结束失败（1）：这张卡已不属于当前进程。'
        + '根因是 lifeCycleMode 默认 STOP_BY_APP，卡片不随进程回收。';
    }
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
