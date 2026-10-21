import { AuthUser } from './model/Auth';
import { ApiClient } from './net/ApiClient';
import { DashboardWatcher } from './net/DashboardWatcher';
import { Prefs } from './store/Prefs';
import { TokenVault } from './store/TokenVault';
import { Demo } from './Demo';

/** Process-wide app state: server URL, session token, signed-in user. */
export class AppState {
  private static _shared: AppState | null = null;
  static get shared(): AppState {
    if (AppState._shared === null) {
      AppState._shared = new AppState();
    }
    return AppState._shared;
  }

  serverUrl: string = '';
  token: string = '';
  user: AuthUser | null = null;
  restoring: boolean = false;
  /** Sample-data mode: signed in, but with no server and no token. */
  demo: boolean = false;

  get signedIn(): boolean {
    return this.token.length > 0 || this.demo;
  }

  /** Opens the sample account. Keeps any real session so it can be returned to. */
  enterDemo(): void {
    this.demo = true;
    Demo.enter();
    if (this.user === null) {
      this.user = Demo.user();
    }
    AppStorage.setOrCreate('aa_signed_in', true);
    // Restart rather than start: the watcher is already running when this is
    // entered from Settings, and `start()` is a no-op in that case — so the
    // sample inventory would never replace the real one.
    DashboardWatcher.shared.stop();
    DashboardWatcher.shared.start();
  }

  /** Returns to the real account when there is one, otherwise to the login screen. */
  exitDemo(): void {
    this.demo = false;
    Demo.exit();
    this.user = null;
    DashboardWatcher.shared.stop();
    DashboardWatcher.shared.start();
    AppStorage.setOrCreate('aa_signed_in', this.signedIn);
  }

  /** Loads server URL + encrypted token; the token is decrypted off the UI thread. */
  async restore(): Promise<void> {
    if (this.restoring) {
      return;
    }
    this.restoring = true;
    try {
      this.serverUrl = Prefs.getString(Prefs.keys.serverUrl, '');
      if (this.serverUrl.length > 0) {
        ApiClient.configure(this.serverUrl, '');
      }
      const token = await TokenVault.load();
      if (token !== null && this.serverUrl.length > 0) {
        this.token = token;
        ApiClient.configure(this.serverUrl, token);
        if (!Demo.on()) {
          const me = await ApiClient.shared.get('/auth/me').catch(() => null);
          if (me !== null) {
            this.user = AuthUser.fromJson(me);
          }
        }
      }
    } finally {
      this.restoring = false;
    }
    if (Demo.on()) {
      this.demo = true;
      if (this.user === null) {
        this.user = Demo.user();
      }
      AppStorage.setOrCreate('aa_signed_in', true);
      DashboardWatcher.shared.start();
    }
  }

  /** Persists a fresh sign-in and rebinds the HTTP client. */
  async signIn(serverUrl: string, token: string, user: AuthUser): Promise<void> {
    this.serverUrl = ApiClient.normalizeBase(serverUrl);
    this.token = token;
    this.user = user;
    Prefs.putString(Prefs.keys.serverUrl, this.serverUrl);
    Prefs.putString(Prefs.keys.userId, user.userId);
    Prefs.putString(Prefs.keys.displayName, user.displayName);
    if (user.email !== null) {
      Prefs.putString(Prefs.keys.email, user.email as string);
    }
    Prefs.putString(Prefs.keys.role, user.role);
    await TokenVault.save(token);
    ApiClient.configure(this.serverUrl, token);
    // Index gates Login vs MainTabs on this key; without it the UI stays on Login.
    AppStorage.setOrCreate('aa_signed_in', true);
    DashboardWatcher.shared.start();
  }

  async signOut(): Promise<void> {
    this.token = '';
    this.user = null;
    this.demo = false;
    Demo.exit();
    DashboardWatcher.shared.stop();
    await TokenVault.clear();
    ApiClient.reset();
    AppStorage.setOrCreate('aa_signed_in', false);
  }
}
