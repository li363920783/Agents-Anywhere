import util from '@ohos.util';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Json } from '../util/Json';
import { Fmt } from '../util/Fmt';
import { SessionView } from '../model/Session';
import { Prefs } from '../store/Prefs';
import { RealtimeStream, RealtimeCallbacks } from './RealtimeStream';
import { ApiClient } from './ApiClient';
import { Notifier } from '../notify/Notifier';
import { KeepAlive } from '../notify/KeepAlive';
import { LiveView } from '../notify/LiveView';

const TAG = 'AA-Watch';
/** Statuses that mean a turn is in flight. */
const ACTIVE_STATUSES: Array<string> = ['running', 'pending', 'stopping', 'waiting'];
const RECONNECT_MIN_MS = 2000;
const RECONNECT_MAX_MS = 60000;

/** AppStorage key holding the unread count the tab bar badges. */
export const UNREAD_KEY = 'aa_unread';
/**
 * AppStorage key holding the full workspace inventory. `list_session_inventory`
 * is unpaginated and has no archived filter, so one socket covers what the
 * paged `/sessions` endpoint could only deliver 100 rows at a time.
 */
export const SESSIONS_KEY = 'aa_sessions';

function displayTitle(s: SessionView): string {
  const t = s.title;
  if (t !== null && t.trim().length > 0) {
    return t.trim();
  }
  const parts = (s.cwd ?? '').split(/[\\/]/).filter((p: string) => p.length > 0);
  if (parts.length > 0) {
    return parts[parts.length - 1];
  }
  return `${s.runtime} session`;
}

/**
 * App-wide dashboard socket. The session list and the detail page each own
 * their own data; this exists only to turn server-side state *transitions* into
 * notifications, an unread badge, and a keep-alive for running turns.
 *
 * Reconnects with backoff — a monitoring socket that dies silently is worse
 * than no socket, because the user trusts it.
 */
export class DashboardWatcher {
  private static _shared: DashboardWatcher | null = null;
  static get shared(): DashboardWatcher {
    if (DashboardWatcher._shared === null) {
      DashboardWatcher._shared = new DashboardWatcher();
    }
    return DashboardWatcher._shared;
  }

  /** The session currently on screen: never notify about what the user is reading. */
  activeSessionId: string = '';

  /** `id` -> `status|unread` for the previous snapshot. */
  private prev: Record<string, string> = {};
  private stream: RealtimeStream | null = null;
  private seeded: boolean = false;
  private wantRun: boolean = false;
  private retryTimer: number = -1;
  private backoff: number = RECONNECT_MIN_MS;

  start(): void {
    if (this.wantRun) {
      return;
    }
    this.wantRun = true;
    // The watcher only runs for a signed-in user, which is exactly when asking
    // for notification permission makes sense.
    Notifier.askOnce();
    this.connect();
  }

  stop(): void {
    this.wantRun = false;
    this.clearRetry();
    if (this.stream !== null) {
      this.stream.stop();
      this.stream = null;
    }
    this.seeded = false;
    this.prev = {};
    AppStorage.setOrCreate(SESSIONS_KEY, []);
    AppStorage.setOrCreate(UNREAD_KEY, 0);
    KeepAlive.sync(false);
  }

  /** Pull-to-refresh: the socket pushes on change, so a resync means a reconnect. */
  reconnect(): void {
    if (!this.wantRun) {
      this.start();
      return;
    }
    this.clearRetry();
    if (this.stream !== null) {
      this.stream.stop();
      this.stream = null;
    }
    // The next snapshot is a fresh baseline, not a diff against stale state.
    this.seeded = false;
    this.prev = {};
    this.backoff = RECONNECT_MIN_MS;
    this.connect();
  }

  private connect(): void {
    if (!this.wantRun || !ApiClient.configured) {
      return;
    }
    const cb = new RealtimeCallbacks();
    cb.onOpen = () => {
      this.backoff = RECONNECT_MIN_MS;
    };
    cb.onText = (text: string) => this.handleFrame(text);
    cb.onClose = (code: number, reason: string) => {
      hilog.warn(0x0000, TAG, 'dashboard closed %{public}d %{public}s', code, reason);
      this.scheduleReconnect();
    };
    cb.onError = (msg: string) => {
      hilog.warn(0x0000, TAG, 'dashboard error %{public}s', msg);
    };
    const stream = new RealtimeStream(null, cb);
    this.stream = stream;
    stream.start(util.generateRandomUUID()).catch((e: Error) => {
      hilog.warn(0x0000, TAG, 'dashboard start %{public}s', e.message);
      this.scheduleReconnect();
    });
  }

  private scheduleReconnect(): void {
    if (!this.wantRun || this.retryTimer !== -1) {
      return;
    }
    const delay = this.backoff;
    this.backoff = Math.min(this.backoff * 2, RECONNECT_MAX_MS);
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1;
      if (this.stream !== null) {
        this.stream.stop();
        this.stream = null;
      }
      this.connect();
    }, delay);
  }

  private clearRetry(): void {
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private handleFrame(text: string): void {
    const frame = Json.parse(text);
    if (frame === null || Json.str(frame, 'type') !== 'dashboard.snapshot') {
      return;
    }
    const raw = Json.arr(frame, 'sessions') ?? [];
    const sessions: Array<SessionView> = [];
    for (let i = 0; i < raw.length; i++) {
      sessions.push(SessionView.fromJson(raw[i]));
    }
    this.applySnapshot(sessions);
  }

  /**
   * Diffs the new snapshot against the last one. The first snapshot only seeds:
   * whatever was already unread when the app opened is not news.
   */
  private applySnapshot(sessions: Array<SessionView>): void {
    const next: Record<string, string> = {};
    let unread = 0;
    let active = 0;
    let running: SessionView | null = null;
    for (let i = 0; i < sessions.length; i++) {
      const s = sessions[i];
      if (s.archived) {
        continue;
      }
      next[s.id] = `${s.status}|${s.unread ? 1 : 0}`;
      if (s.unread) {
        unread++;
      }
      if (ACTIVE_STATUSES.indexOf(s.status) >= 0) {
        active++;
        // The live view shows one turn: the most recent one to start running.
        if (running === null || (s.lastActivityAt ?? '') > (running.lastActivityAt ?? '')) {
          running = s;
        }
      }
    }

    const seeding = !this.seeded;
    this.seeded = true;
    if (!seeding) {
      for (let i = 0; i < sessions.length; i++) {
        this.diffOne(sessions[i], next[sessions[i].id]);
      }
    }
    this.prev = next;

    AppStorage.setOrCreate(SESSIONS_KEY, sessions);
    AppStorage.setOrCreate(UNREAD_KEY, unread);
    void Notifier.setBadge(unread);
    KeepAlive.sync(active > 0);
    if (running === null) {
      void LiveView.hide();
    } else {
      const live = running as SessionView;
      void LiveView.show(displayTitle(live), `${Fmt.statusLabel(live.status)} · ${live.runtime}`);
    }
  }

  private diffOne(s: SessionView, after: string): void {
    if (s.archived || s.id === this.activeSessionId) {
      return;
    }
    const before = this.prev[s.id];
    if (before === after) {
      return;
    }
    const beforeStatus = before === undefined ? '' : before.split('|')[0];
    const beforeUnread = before !== undefined && before.endsWith('|1');

    if (s.status === 'waiting_approval' && beforeStatus !== 'waiting_approval') {
      if (Prefs.getBool(Prefs.keys.notifyApproval, true)) {
        void Notifier.notify(s, '需要审批', `${displayTitle(s)} 正在等待你的确认`);
      }
      return;
    }
    // A turn end re-arms `unread`; that flip is the "the agent finished" signal.
    if (s.unread && !beforeUnread && Prefs.getBool(Prefs.keys.notifyDone, true)) {
      void Notifier.notify(s, displayTitle(s), `已完成 · ${Fmt.statusLabel(s.status)}`);
    }
  }
}
