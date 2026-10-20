import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';

interface PrefsKeys {
  serverUrl: string;
  tokenState: string;
  userId: string;
  displayName: string;
  email: string;
  role: string;
  onboarded: string;
  appearance: string;
}

/** App preferences: server URL, recent servers, appearance. */
export class Prefs {
  private static store: preferences.Preferences | null = null;
  private static readonly NAME = 'aa_harmony';

  static keys: PrefsKeys = {
    serverUrl: 'server_url',
    tokenState: 'token_state',
    userId: 'user_id',
    displayName: 'display_name',
    email: 'email',
    role: 'role',
    onboarded: 'onboarded',
    appearance: 'appearance'
  };

  static init(context: common.UIAbilityContext): void {
    if (Prefs.store === null) {
      Prefs.store = preferences.getPreferencesSync(context, { name: Prefs.NAME });
    }
  }

  static getString(key: string, def: string): string {
    const s = Prefs.store;
    if (s === null) {
      return def;
    }
    return s.getSync(key, def) as string;
  }

  static putString(key: string, value: string): void {
    const s = Prefs.store;
    if (s === null) {
      return;
    }
    s.putSync(key, value);
    s.flush();
  }

  static getBool(key: string, def: boolean): boolean {
    const s = Prefs.store;
    if (s === null) {
      return def;
    }
    return s.getSync(key, def) as boolean;
  }

  static putBool(key: string, value: boolean): void {
    const s = Prefs.store;
    if (s === null) {
      return;
    }
    s.putSync(key, value);
    s.flush();
  }

  static delete(key: string): void {
    const s = Prefs.store;
    if (s === null) {
      return;
    }
    s.deleteSync(key);
    s.flush();
  }
}
