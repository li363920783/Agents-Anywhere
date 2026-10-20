import util from '@ohos.util';

/** Base64url + UTF-8 helpers used by the auth verifier and token vault. */
export class B64 {
  private static helper(): util.Base64Helper {
    return new util.Base64Helper();
  }

  static bytesToUrl(bytes: Uint8Array): string {
    const std = B64.helper().encodeToStringSync(bytes);
    return std.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  static urlToBytes(s: string): Uint8Array {
    const std = s.replace(/-/g, '+').replace(/_/g, '/');
    const rest = std.length % 4;
    const padded = rest === 0 ? std : std + '='.repeat(4 - rest);
    return B64.helper().decodeSync(padded);
  }

  static strToBytes(s: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(s);
  }

  static bytesToUrlStd(bytes: Uint8Array): string {
    return B64.helper().encodeToStringSync(bytes);
  }

  static urlStdToBytes(s: string): Uint8Array {
    return B64.helper().decodeSync(s);
  }
}
