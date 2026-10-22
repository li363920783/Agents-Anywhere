import { asset } from '@kit.AssetStoreKit';
import util from '@ohos.util';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'AA-Vault';
const ALIAS = 'com.morin.clauderelay.token';
/** Long-lived refresh credential. Same protection as the access token: it is
 *  a bearer secret, not a cacheable id. */
const ALIAS_REFRESH = 'com.morin.clauderelay.refresh';
const LABEL = 'auth-token';

function utf8(text: string): Uint8Array {
  return new util.TextEncoder().encodeInto(text);
}

/**
 * Auth token vault backed by AssetStoreKit.
 *
 * The system keystore stores the secret encrypted and ties it to this app, so
 * the token survives restarts without this code handling key material at all.
 * (The previous HUKS AES-GCM implementation could write a token but never read
 * it back — `finishSession` on decrypt failed with "parameter does not exist".)
 */
export class TokenVault {
  private static aliasQuery(alias: string): asset.AssetMap {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, utf8(alias));
    return query;
  }

  static async save(token: string): Promise<void> {
    await TokenVault.write(ALIAS, token);
  }

  static async saveRefresh(token: string): Promise<void> {
    await TokenVault.write(ALIAS_REFRESH, token);
  }

  private static async write(alias: string, token: string): Promise<void> {
    // `add` rejects a duplicate alias, so replace the entry outright.
    await TokenVault.remove(alias);
    const attrs: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attrs.set(asset.Tag.ALIAS, utf8(alias));
    attrs.set(asset.Tag.SECRET, utf8(token));
    attrs.set(asset.Tag.DATA_LABEL_NORMAL_1, utf8(LABEL));
    // Readable once the device has been unlocked at least once, so a background
    // reconnect after a reboot does not demand a fresh sign-in.
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    await asset.add(attrs);
  }

  static async load(): Promise<string | null> {
    return TokenVault.read(ALIAS);
  }

  static async loadRefresh(): Promise<string | null> {
    return TokenVault.read(ALIAS_REFRESH);
  }

  private static async read(alias: string): Promise<string | null> {
    const query = TokenVault.aliasQuery(alias);
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows = await asset.query(query);
      if (rows.length === 0) {
        return null;
      }
      const secret = rows[0].get(asset.Tag.SECRET);
      if (!(secret instanceof Uint8Array)) {
        return null;
      }
      return new util.TextDecoder('utf-8').decodeToString(secret);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'query: %{public}s', (e as Error).message);
      return null;
    }
  }

  private static async remove(alias: string): Promise<void> {
    try {
      await asset.remove(TokenVault.aliasQuery(alias));
    } catch (e) {
      // Not found is the normal path on a fresh install.
      hilog.info(0x0000, TAG, 'remove: %{public}s', (e as Error).message);
    }
  }

  static async clear(): Promise<void> {
    await TokenVault.remove(ALIAS);
    await TokenVault.remove(ALIAS_REFRESH);
  }
}
