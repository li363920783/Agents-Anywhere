import { Json } from '../util/Json';

/** Auth wire models, matching `server/agent_server/api/auth.py` responses. */
export class AuthConfig {
  registrationOpen: boolean = false;
  emailVerificationRequired: boolean = false;
  oauthEnabled: boolean = false;
  passwordResetEnabled: boolean = false;
  serverTime: string = '';

  static fromJson(o: Object | null): AuthConfig {
    const m = new AuthConfig();
    m.registrationOpen = Json.bool(o, 'registrationOpen') ?? false;
    m.emailVerificationRequired = Json.bool(o, 'emailVerificationRequired') ?? false;
    m.oauthEnabled = Json.bool(o, 'oauthEnabled') ?? false;
    m.passwordResetEnabled = Json.bool(o, 'passwordResetEnabled') ?? false;
    m.serverTime = Json.strOr(o, 'serverTime', '');
    return m;
  }
}

export class PasswordSaltResponse {
  salt: string = '';
  serverTime: string = '';

  static fromJson(o: Object | null): PasswordSaltResponse {
    const m = new PasswordSaltResponse();
    m.salt = Json.strOr(o, 'salt', '');
    m.serverTime = Json.strOr(o, 'serverTime', '');
    return m;
  }
}

export class AuthUser {
  userId: string = '';
  email: string | null = null;
  displayName: string = '';
  role: string = 'member';

  static fromJson(o: Object | null): AuthUser {
    const m = new AuthUser();
    m.userId = Json.strOr(o, 'userId', '');
    m.email = Json.str(o, 'email');
    m.displayName = Json.strOr(o, 'displayName', '');
    m.role = Json.strOr(o, 'role', 'member');
    return m;
  }
}

export class AuthResponse {
  user: AuthUser = new AuthUser();
  accessToken: string = '';
  tokenType: string = '';
  serverTime: string = '';

  static fromJson(o: Object | null): AuthResponse {
    const m = new AuthResponse();
    m.user = AuthUser.fromJson(o);
    m.accessToken = Json.strOr(o, 'accessToken', '');
    m.tokenType = Json.strOr(o, 'tokenType', 'bearer');
    m.serverTime = Json.strOr(o, 'serverTime', '');
    return m;
  }
}

/**
 * Redeems a refresh token for a new access token.
 *
 * The server endpoint does not exist yet (tracked with 老四). The client is
 * written against the shape below and tolerates a response that omits
 * `refreshToken` — in that case the current one is kept, which is what a
 * non-rotating server returns.
 */
export class AuthRefreshRequest {
  refreshToken: string = '';
}

export class AuthRefreshResponse {
  accessToken: string = '';
  /** Present only when the server rotates; empty means "keep the old one". */
  refreshToken: string = '';
  expiresAt: string = '';

  static fromJson(o: Object | null): AuthRefreshResponse {
    const m = new AuthRefreshResponse();
    m.accessToken = Json.strOr(o, 'accessToken', '');
    m.refreshToken = Json.strOr(o, 'refreshToken', '');
    m.expiresAt = Json.strOr(o, 'expiresAt', '');
    return m;
  }
}

export class MobileLoginStatusResponse {
  status: string = 'expired';

  static fromJson(o: Object | null): MobileLoginStatusResponse {
    const m = new MobileLoginStatusResponse();
    m.status = Json.strOr(o, 'status', 'expired');
    return m;
  }
}

export class MobileLoginExchangeResponse {
  auth: AuthResponse = new AuthResponse();
  refreshToken: string = '';
  expiresAt: string = '';

  static fromJson(o: Object | null): MobileLoginExchangeResponse {
    const m = new MobileLoginExchangeResponse();
    m.auth = AuthResponse.fromJson(Json.obj(o, 'auth'));
    m.refreshToken = Json.strOr(o, 'refreshToken', '');
    m.expiresAt = Json.strOr(o, 'expiresAt', '');
    return m;
  }
}
