import huks from '@ohos.security.huks';
import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { B64 } from '../util/B64';
import { Prefs } from './Prefs';

/**
 * Auth token vault: AES-256-GCM via HUKS hardware keystore.
 * Ciphertext + tag stored in preferences; the key never leaves the keystore.
 */
export class TokenVault {
  private static readonly ALIAS = 'com.morin.agentsanywhere.token.v1';
  private static readonly NONCE_BYTES = 12;
  private static ready: boolean = false;

  private static aesGcmProps(purpose: number, extra: huks.HuksParam[]): huks.HuksParam[] {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      ...extra
    ];
  }

  private static ensureKey(): Promise<void> {
    if (TokenVault.ready) {
      return Promise.resolve();
    }
    const options: huks.HuksOptions = {
      properties: TokenVault.aesGcmProps(
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT,
        []
      )
    };
    return huks
      .generateKeyItem(TokenVault.ALIAS, options)
      .then(() => {
        TokenVault.ready = true;
      })
      .catch((err: Error) => {
        // A key that already exists is fine; any other failure surfaces to the caller.
        if (`${err.message}`.includes('already exist') || `${err.message}`.includes('-128')) {
          TokenVault.ready = true;
          return;
        }
        throw err;
      });
  }

  static async save(token: string): Promise<void> {
    await TokenVault.ensureKey();
    const plaintext = B64.strToBytes(token);
    const nonce = new Uint8Array(TokenVault.NONCE_BYTES);
    const rand = cryptoFramework.createRandom().generateRandomSync(nonce.length);
    if (rand.data !== undefined) {
      nonce.set(rand.data);
    }
    const handle = await huks.initSession(TokenVault.ALIAS, {
      properties: TokenVault.aesGcmProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, [
        { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce }
      ]),
      inData: new Uint8Array(0)
    });
    const out = await huks.finishSession(handle.handle, {
      properties: TokenVault.aesGcmProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, []),
      inData: plaintext
    });
    Prefs.putString(Prefs.keys.tokenState, `${B64.bytesToUrl(nonce)}.${B64.bytesToUrlStd(out.outData ?? new Uint8Array(0))}`);
  }

  static async load(): Promise<string | null> {
    const state = Prefs.getString(Prefs.keys.tokenState, '');
    if (state.length === 0) {
      return null;
    }
    const parts = state.split('.');
    if (parts.length !== 2) {
      return null;
    }
    try {
      await TokenVault.ensureKey();
      const nonce = B64.urlToBytes(parts[0]);
      const cipher = B64.urlStdToBytes(parts[1]);
      const handle = await huks.initSession(TokenVault.ALIAS, {
        properties: TokenVault.aesGcmProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, [
          { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce }
        ]),
        inData: new Uint8Array(0)
      });
      const out = await huks.finishSession(handle.handle, {
        properties: TokenVault.aesGcmProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, []),
        inData: cipher
      });
      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(out.outData);
    } catch (e) {
      return null;
    }
  }

  static async clear(): Promise<void> {
    Prefs.delete(Prefs.keys.tokenState);
    TokenVault.ready = false;
    await huks.deleteKeyItem(TokenVault.ALIAS, {} as huks.HuksOptions).catch(() => {});
  }
}
