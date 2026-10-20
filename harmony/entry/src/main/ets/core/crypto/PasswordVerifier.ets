import cryptoFramework from '@ohos.security.cryptoFramework';
import { B64 } from '../util/B64';

/**
 * Password verifier: PBKDF2-SHA256(password, serverSalt, 120000, 32B) base64url.
 * Byte-for-byte identical derivation to the web client's `password-verifier.ts`.
 */
export class PasswordVerifier {
  private static readonly ITERATIONS = 120000;
  /** PBKDF2Spec.keySize is in BYTES, not bits. 32 bytes = the server's SHA-256 dkLen. */
  private static readonly KEY_BYTES = 32;

  static async derive(password: string, salt: string): Promise<string> {
    const kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: B64.strToBytes(password),
      salt: B64.strToBytes(salt),
      keySize: PasswordVerifier.KEY_BYTES,
      iterations: PasswordVerifier.ITERATIONS
    };
    const blob = await kdf.generateSecret(spec);
    return B64.bytesToUrl(blob.data ?? new Uint8Array(0));
  }
}
