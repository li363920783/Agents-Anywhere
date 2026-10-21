import { Theme } from '../ui/Theme';

/** Relative-time formatting for session rows (mirrors the iOS client). */
export class Fmt {
  static relTime(iso: string | null, nowMs: number): string {
    if (iso === null || iso.length === 0) {
      return '';
    }
    const t = Date.parse(iso);
    if (isNaN(t)) {
      return '';
    }
    const delta = Math.max(0, nowMs - t);
    const min = Math.floor(delta / 60000);
    if (min < 1) {
      return 'now';
    }
    if (min < 60) {
      return `${min}m`;
    }
    const hr = Math.floor(min / 60);
    if (hr < 24) {
      return `${hr}h`;
    }
    const day = Math.floor(hr / 24);
    if (day < 30) {
      return `${day}d`;
    }
    return `${Math.floor(day / 30)}mo`;
  }

  static statusLabel(status: string): string {
    switch (status) {
      case 'idle':
        return 'Idle';
      case 'waiting':
        return 'Waiting';
      case 'pending':
        return 'Pending';
      case 'running':
        return 'Running';
      case 'stopping':
        return 'Stopping';
      case 'waiting_approval':
        return 'Needs approval';
      case 'error':
        return 'Error';
      case 'blocked':
        return 'Blocked';
      default:
        return status;
    }
  }

  /**
   * Chip colour for a session status. Distinct hues rather than one accent:
   * scanning a long list, the colour has to say which session wants attention
   * before the label is read.
   */
  static statusColor(status: string): string {
    switch (status) {
      case 'running':
        return Theme.busy;
      case 'pending':
      case 'stopping':
        return Theme.stalled;
      case 'waiting':
      case 'waiting_approval':
        return Theme.waiting;
      case 'error':
      case 'blocked':
        return Theme.bad;
      case 'idle':
        return Theme.idle;
      default:
        return Theme.neutral;
    }
  }

  /** True while the state is still changing, so the dot pulses. */
  static statusLive(status: string): boolean {
    return status === 'running' || status === 'pending' || status === 'waiting_approval';
  }

  static linkColor(online: boolean): string {
    return online ? Theme.ok : Theme.neutral;
  }
}
