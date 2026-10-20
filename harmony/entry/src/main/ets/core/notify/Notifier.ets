import { notificationManager } from '@kit.NotificationKit';
import { wantAgent, common, Want, WantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SessionView } from '../model/Session';
import { Prefs } from '../store/Prefs';

const TAG = 'AA-Notifier';
const BUNDLE_NAME = 'com.morin.agentsanywhere';
const ABILITY_NAME = 'EntryAbility';
const GROUP = 'aa-sessions';

/** EntryAbility reads this want parameter to open the session a notification points at. */
export const WANT_SESSION_KEY = 'aaSessionId';

/**
 * Stable per-session notification id. Publishing with the same id replaces the
 * previous alert for that session instead of stacking a new one.
 */
function notificationId(sessionId: string): number {
  let h = 7;
  for (let i = 0; i < sessionId.length; i++) {
    h = (h * 31 + sessionId.charCodeAt(i)) | 0;
  }
  return (h & 0x7fffffff) % 100000 + 1;
}

/**
 * Local notifications for session attention. The app has no push channel, so
 * these fire from the in-process dashboard watcher: they only reach the user
 * while the process is alive (see `KeepAlive`).
 */
export class Notifier {
  private static slotReady: boolean = false;
  private static context: common.UIAbilityContext | null = null;

  /** Held so the opt-in prompt can fire once the user is actually signed in. */
  static attach(context: common.UIAbilityContext): void {
    Notifier.context = context;
  }

  /**
   * Asks once, and only once the user is signed in — a first-run user sees the
   * login screen first, so asking from `onCreate` would never happen.
   */
  static askOnce(): void {
    const ctx = Notifier.context;
    if (ctx === null || Prefs.getBool(Prefs.keys.notifyAsked, false)) {
      return;
    }
    Prefs.putBool(Prefs.keys.notifyAsked, true);
    void Notifier.requestEnable(ctx);
  }

  /** Whether the user has notifications switched on for this app at all. */
  static async isEnabled(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (e) {
      hilog.warn(0x0000, TAG, 'isNotificationEnabled: %{public}s', (e as Error).message);
      return false;
    }
  }

  /**
   * Shows the system opt-in dialog. Publishes are dropped silently while this
   * is off, so it is worth asking once rather than letting alerts vanish.
   */
  static async requestEnable(context: common.UIAbilityContext): Promise<boolean> {
    try {
      if (await Notifier.isEnabled()) {
        return true;
      }
      await notificationManager.requestEnableNotification(context);
      return await Notifier.isEnabled();
    } catch (e) {
      hilog.warn(0x0000, TAG, 'requestEnableNotification: %{public}s', (e as Error).message);
      return false;
    }
  }

  private static async ensureSlot(): Promise<void> {
    if (Notifier.slotReady) {
      return;
    }
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
    } catch (e) {
      // Adding an existing slot is rejected; publishing still works.
      hilog.warn(0x0000, TAG, 'addSlot: %{public}s', (e as Error).message);
    }
    Notifier.slotReady = true;
  }

  /** Tapping the notification opens EntryAbility carrying the session id. */
  private static async tapAgent(sessionId: string): Promise<WantAgent | null> {
    try {
      // Built by index assignment: ArkTS rejects a bare literal for
      // `Want.parameters` (`arkts-no-untyped-obj-literals`).
      const params: Record<string, Object> = {};
      params[WANT_SESSION_KEY] = sessionId;
      const want: Want = {
        bundleName: BUNDLE_NAME,
        abilityName: ABILITY_NAME,
        parameters: params
      };
      const info: wantAgent.WantAgentInfo = {
        wants: [want],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: notificationId(sessionId),
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      return await wantAgent.getWantAgent(info);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'getWantAgent: %{public}s', (e as Error).message);
      return null;
    }
  }

  /** Posts (or replaces) the notification for one session. */
  static async notify(session: SessionView, title: string, text: string): Promise<void> {
    await Notifier.ensureSlot();
    const agent = await Notifier.tapAgent(session.id);
    const req: notificationManager.NotificationRequest = {
      id: notificationId(session.id),
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: title, text: text }
      },
      tapDismissed: true,
      groupName: GROUP
    };
    if (agent !== null) {
      req.wantAgent = agent;
    }
    try {
      await notificationManager.publish(req);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'publish: %{public}s', (e as Error).message);
    }
  }

  static async clear(sessionId: string): Promise<void> {
    try {
      await notificationManager.cancel(notificationId(sessionId));
    } catch (e) {
      hilog.warn(0x0000, TAG, 'cancel: %{public}s', (e as Error).message);
    }
  }

  static async clearAll(): Promise<void> {
    try {
      await notificationManager.cancelAll();
    } catch (e) {
      hilog.warn(0x0000, TAG, 'cancelAll: %{public}s', (e as Error).message);
    }
  }

  /** Launcher badge — the user's at-a-glance "something needs me" count. */
  static async setBadge(count: number): Promise<void> {
    try {
      await notificationManager.setBadgeNumber(count);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'setBadgeNumber: %{public}s', (e as Error).message);
    }
  }
}
