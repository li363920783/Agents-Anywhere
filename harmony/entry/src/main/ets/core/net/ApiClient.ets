import http from '@ohos.net.http';
import util from '@ohos.util';
import { Json } from '../util/Json';
import { ApiError } from './ApiError';
import { Demo } from '../Demo';
import { EmptyBody, WsTicketRequest } from '../model/Bodies';
import { AuthRefreshRequest, AuthRefreshResponse } from '../model/Auth';

/** Refresh this long before the access token's own `exp`. */
const REFRESH_LEAD_MS = 60 * 1000;

/**
 * Typed v2 HTTP client. Mirrors the iOS `V2APIClient` surface:
 * `request` throws `ApiError` for transport or non-2xx responses.
 */
export class ApiClient {
  private static instance: ApiClient | null = null;
  private static readonly V2 = '/api/v2';
  private baseUrl: string = '';
  private token: string = '';
  private refreshToken: string = '';
  /** Access-token expiry in epoch ms, read from the JWT's own `exp`. */
  private accessExpiresAtMs: number = 0;
  /**
   * The in-flight refresh. Several requests can hit 401 in the same burst;
   * with rotating refresh tokens each extra refresh would invalidate the
   * other's, so every caller waits on the same one.
   */
  private refreshing: Promise<boolean> | null = null;
  /** Persists a rotated credential pair; supplied by the session owner. */
  private persistSession: ((access: string, refresh: string) => Promise<void>) | null = null;
  /** Fires only when the session cannot be recovered (401/403 from refresh). */
  private sessionExpired: (() => void) | null = null;
  private readonly req: http.HttpRequest;

  constructor(baseUrl: string, token: string) {
    this.baseUrl = ApiClient.normalizeBase(baseUrl);
    this.token = token;
    this.req = http.createHttp();
  }

  static normalizeBase(baseUrl: string): string {
    let b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.slice(0, -1);
    }
    return b;
  }

  /** v2 namespace prefix, mirroring the iOS transport's `v2Namespace` normalization. */
  static namespaced(path: string): string {
    const normalized = path.startsWith('/') ? path : `/${path}`;
    if (normalized === ApiClient.V2 || normalized.startsWith(`${ApiClient.V2}/`)) {
      return normalized;
    }
    return `${ApiClient.V2}${normalized}`;
  }

  static get shared(): ApiClient {
    if (ApiClient.instance === null) {
      throw new Error('ApiClient is not configured');
    }
    return ApiClient.instance;
  }

  static get configured(): boolean {
    return ApiClient.instance !== null;
  }

  static configure(baseUrl: string, token: string): ApiClient {
    if (ApiClient.instance !== null) {
      ApiClient.instance.req.destroy();
    }
    ApiClient.instance = new ApiClient(baseUrl, token);
    return ApiClient.instance;
  }

  static reset(): void {
    if (ApiClient.instance !== null) {
      ApiClient.instance.req.destroy();
      ApiClient.instance = null;
    }
  }

  get serverBase(): string {
    return this.baseUrl;
  }

  updateToken(token: string): void {
    this.token = token;
    this.accessExpiresAtMs = ApiClient.tokenExpiryMs(token);
  }

  /** Binds the credential pair and the callbacks that keep it durable. */
  setSession(
    accessToken: string,
    refreshToken: string,
    persist: ((access: string, refresh: string) => Promise<void>) | null,
    expired: (() => void) | null,
  ): void {
    this.updateToken(accessToken);
    this.refreshToken = refreshToken;
    this.persistSession = persist;
    this.sessionExpired = expired;
  }

  /** JWT `exp` in epoch ms, or 0 when the token is not a JWT. */
  private static tokenExpiryMs(token: string): number {
    const parts = token.split('.');
    if (parts.length < 2) {
      return 0;
    }
    try {
      let b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      while (b64.length % 4 !== 0) {
        b64 += '=';
      }
      const json = new util.TextDecoder('utf-8').decodeToString(
        new util.Base64Helper().decodeSync(b64)
      );
      const exp = Json.num(Json.parse(json), 'exp');
      return exp === null ? 0 : exp * 1000;
    } catch (e) {
      return 0;
    }
  }

  private needsRefresh(): boolean {
    if (this.refreshToken.length === 0 || this.accessExpiresAtMs === 0) {
      return false;
    }
    return Date.now() >= this.accessExpiresAtMs - REFRESH_LEAD_MS;
  }

  /**
   * Single-flight refresh. Returns true when a usable access token is in hand.
   * Never throws: a failed refresh leaves the caller to surface the original
   * error, and only 401/403 ends the session (a dead network must not sign the
   * user out).
   */
  private async refreshSession(): Promise<boolean> {
    if (this.refreshToken.length === 0) {
      return false;
    }
    const inFlight = this.refreshing;
    if (inFlight !== null) {
      return inFlight;
    }
    const run = this.performRefresh();
    this.refreshing = run;
    try {
      return await run;
    } finally {
      if (this.refreshing === run) {
        this.refreshing = null;
      }
    }
  }

  private async performRefresh(): Promise<boolean> {
    const body = new AuthRefreshRequest();
    body.refreshToken = this.refreshToken;
    try {
      const parsed = AuthRefreshResponse.fromJson(
        await this.send(http.RequestMethod.POST, '/auth/refresh', body, false)
      );
      if (parsed.accessToken.length === 0) {
        return false;
      }
      // Rotation: the server may hand back a new refresh token, and the old one
      // is dead the moment it does. Losing it here means the next refresh 401s.
      const rotated = parsed.refreshToken.length > 0 ? parsed.refreshToken : this.refreshToken;
      this.token = parsed.accessToken;
      this.refreshToken = rotated;
      this.accessExpiresAtMs = ApiClient.tokenExpiryMs(parsed.accessToken);
      if (this.persistSession !== null) {
        await this.persistSession(parsed.accessToken, rotated);
      }
      return true;
    } catch (e) {
      const err = e as Error;
      if (err instanceof ApiError && (err.httpCode === 401 || err.httpCode === 403)) {
        this.refreshToken = '';
        if (this.sessionExpired !== null) {
          this.sessionExpired();
        }
      }
      return false;
    }
  }

  /**
   * Request policy over `send`: refresh a token that is about to expire, and
   * on a 401 refresh once and replay. Anything else passes through unchanged,
   * so callers still see the original ApiError.
   */
  private async raw(method: http.RequestMethod, path: string, body: Object | null, auth: boolean): Promise<Object> {
    if (auth && this.needsRefresh()) {
      await this.refreshSession();
    }
    try {
      return await this.send(method, path, body, auth);
    } catch (e) {
      const err = e as Error;
      const apiErr = err instanceof ApiError ? err as ApiError : null;
      if (!auth || apiErr === null || apiErr.httpCode !== 401) {
        throw err;
      }
      const recovered = await this.refreshSession();
      if (!recovered) {
        throw err;
      }
      return await this.send(method, path, body, auth);
    }
  }

  private send(method: http.RequestMethod, path: string, body: Object | null, auth: boolean): Promise<Object> {
    if (Demo.on() && method !== http.RequestMethod.GET) {
      // The sample account has no server behind it. Fail here, immediately,
      // rather than after a timeout — the callers already surface the message.
      return Promise.reject(new ApiError(0, '演示模式不支持该操作', ''));
    }
    const url = `${this.baseUrl}${ApiClient.namespaced(path)}`;
    const header: Record<string, string> = { 'Content-Type': 'application/json' };
    if (auth && this.token.length > 0) {
      header['Authorization'] = `Bearer ${this.token}`;
    }
    const options: http.HttpRequestOptions = {
      method: method,
      header: header,
      expectDataType: http.HttpDataType.STRING,
      readTimeout: 30000,
      connectTimeout: 15000
    };
    if (body !== null && !(body instanceof EmptyBody)) {
      options.extraData = JSON.stringify(body);
    }
    return new Promise<Object>((resolve, reject) => {
      this.req.request(url, options, (err: BusinessError, data: http.HttpResponse) => {
        if (err) {
          reject(new ApiError(0, `network: ${err.message}`, ''));
          return;
        }
        const code = data.responseCode;
        if (code < 200 || code >= 300) {
          const text = typeof data.result === 'string' ? data.result : '';
          const parsed = Json.parse(text);
          const detail = Json.str(parsed, 'detail') ?? Json.str(parsed, 'message');
          reject(new ApiError(code, detail ?? `http ${code}`, text));
          return;
        }
        const text = typeof data.result === 'string' ? data.result : '';
        const parsed = Json.parse(text);
        if (parsed === null) {
          resolve(new EmptyBody());
          return;
        }
        resolve(parsed);
      });
    });
  }

  async get(path: string, auth: boolean = true): Promise<Object> {
    return this.raw(http.RequestMethod.GET, path, null, auth);
  }

  async post(path: string, body: Object | null = null, auth: boolean = true): Promise<Object> {
    return this.raw(http.RequestMethod.POST, path, body, auth);
  }

  async put(path: string, body: Object | null = null, auth: boolean = true): Promise<Object> {
    return this.raw(http.RequestMethod.PUT, path, body, auth);
  }

  async patch(path: string, body: Object | null = null, auth: boolean = true): Promise<Object> {
    return this.raw('PATCH' as http.RequestMethod, path, body, auth);
  }

  async del(path: string, auth: boolean = true): Promise<Object> {
    return this.raw(http.RequestMethod.DELETE, path, null, auth);
  }

  async postMultipart(path: string, parts: Array<UploadPart>, auth: boolean = true): Promise<Object> {
    const url = `${this.baseUrl}${ApiClient.namespaced(path)}`;
    const header: Record<string, string> = { 'Content-Type': 'multipart/form-data' };
    if (auth && this.token.length > 0) {
      header['Authorization'] = `Bearer ${this.token}`;
    }
    const list: Array<http.MultiFormData> = [];
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      const item: http.MultiFormData = {
        name: 'files',
        contentType: part.mediaType.length > 0 ? part.mediaType : 'application/octet-stream',
        remoteFileName: part.name,
        data: part.bytes
      };
      list.push(item);
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      expectDataType: http.HttpDataType.STRING,
      multiFormDataList: list,
      readTimeout: 60000,
      connectTimeout: 15000
    };
    return new Promise<Object>((resolve, reject) => {
      this.req.request(url, options, (err: BusinessError, data: http.HttpResponse) => {
        if (err) {
          reject(new ApiError(0, `network: ${err.message}`, ''));
          return;
        }
        const code = data.responseCode;
        const text = typeof data.result === 'string' ? data.result : '';
        if (code < 200 || code >= 300) {
          const parsed = Json.parse(text);
          const detail = Json.str(parsed, 'detail') ?? Json.str(parsed, 'message');
          reject(new ApiError(code, detail ?? `http ${code}`, text));
          return;
        }
        const parsed = Json.parse(text);
        resolve(parsed === null ? new EmptyBody() : parsed);
      });
    });
  }

  /** POST /ws-ticket — one-shot ticket for session/dashboard realtime sockets. */
  async wsTicket(sessionId: string | null, clientId: string): Promise<string> {
    const req = new WsTicketRequest();
    req.clientId = clientId;
    req.scope.sessionId = sessionId;
    req.scope.dashboard = sessionId === null;
    const res = await this.post('/ws-ticket', req);
    return Json.strOr(res, 'ticket', '');
  }
}

export class UploadPart {
  name: string = '';
  mediaType: string = '';
  bytes: ArrayBuffer = new ArrayBuffer(0);

  constructor(name: string, mediaType: string, bytes: ArrayBuffer) {
    this.name = name;
    this.mediaType = mediaType;
    this.bytes = bytes;
  }
}
