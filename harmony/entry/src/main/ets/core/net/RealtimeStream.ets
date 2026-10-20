import webSocket from '@ohos.net.webSocket';
import { ApiClient } from './ApiClient';

export class RealtimeCallbacks {
  onOpen: () => void = () => {};
  onClose: (code: number, reason: string) => void = () => {};
  onError: (msg: string) => void = () => {};
  onText: (text: string) => void = () => {};
}

/**
 * Session/dashboard realtime stream over the v2 WebSocket endpoints.
 * Ticket is exchanged over HTTP first; the 45s silence watchdog mirrors the
 * iOS client (server sends a keepalive frame every ~15s).
 */
export class RealtimeStream {
  private static readonly HEARTBEAT_TIMEOUT_MS = 45000;
  private static readonly TICK_MS = 15000;

  private readonly sessionId: string | null;
  private readonly cb: RealtimeCallbacks;
  private ws: webSocket.WebSocket | null = null;
  private timer: number = -1;
  private lastFrameMs: number = 0;
  private stopped: boolean = true;

  constructor(sessionId: string | null, cb: RealtimeCallbacks) {
    this.sessionId = sessionId;
    this.cb = cb;
  }

  async start(clientId: string): Promise<void> {
    const base = ApiClient.shared.serverBase;
    const ticket = await ApiClient.shared.wsTicket(this.sessionId, clientId);
    const wsBase = base.replace(/^http/, 'ws');
    const path = this.sessionId === null ? '/api/v2/dashboard/ws' : `/api/v2/sessions/${this.sessionId}/ws`;
    const url = `${wsBase}${path}?ticket=${encodeURIComponent(ticket)}`;

    this.stopped = false;
    const sock = webSocket.createWebSocket();
    this.ws = sock;
    sock.on('open', () => {
      this.lastFrameMs = Date.now();
      this.cb.onOpen();
    });
    sock.on('message', (err: BusinessError, data: string | ArrayBuffer) => {
      if (err) {
        this.cb.onError(err.message);
        return;
      }
      if (typeof data !== 'string') {
        return;
      }
      this.lastFrameMs = Date.now();
      this.cb.onText(data);
    });
    sock.on('close', (err: BusinessError, result: webSocket.CloseResult) => {
      this.stopTimer();
      if (!this.stopped) {
        this.cb.onClose(result.code, result.reason);
      }
    });
    sock.on('error', (err: BusinessError) => {
      this.cb.onError(err.message);
    });
    sock.connect(url, (err: BusinessError) => {
      if (err) {
        this.cb.onError(err.message);
      }
    });

    this.timer = setInterval(() => {
      if (this.stopped) {
        return;
      }
      if (Date.now() - this.lastFrameMs >= RealtimeStream.HEARTBEAT_TIMEOUT_MS) {
        this.cb.onError('realtime heartbeat timeout');
        this.stop();
      }
    }, RealtimeStream.TICK_MS);
  }

  sendText(text: string): void {
    this.ws?.send(text);
  }

  stop(): void {
    this.stopped = true;
    this.stopTimer();
    if (this.ws !== null) {
      this.ws.close();
      this.ws = null;
    }
  }

  private stopTimer(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }
}
