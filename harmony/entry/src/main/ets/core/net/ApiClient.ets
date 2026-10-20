import http from '@ohos.net.http';
import { Json } from '../util/Json';
import { ApiError } from './ApiError';
import { EmptyBody, WsTicketRequest } from '../model/Bodies';

/**
 * Typed v2 HTTP client. Mirrors the iOS `V2APIClient` surface:
 * `request` throws `ApiError` for transport or non-2xx responses.
 */
export class ApiClient {
  private static instance: ApiClient | null = null;
  private static readonly V2 = '/api/v2';
  private baseUrl: string = '';
  private token: string = '';
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
  }

  private raw(method: http.RequestMethod, path: string, body: Object | null, auth: boolean): Promise<Object> {
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
