/**
 * Null-safe accessors over decoded JSON trees.
 * Decoded values are `Object`; ArkTS forbids `any`, so every read is typed here.
 */
export class Json {
  static obj(o: Object | null, key: string): Object | null {
    if (o === null) {
      return null;
    }
    const v = (o as Record<string, Object>)[key];
    if (v === null || v === undefined || typeof v !== 'object' || Array.isArray(v)) {
      return null;
    }
    return v as Object;
  }

  static arr(o: Object | null, key: string): Array<Object> | null {
    if (o === null) {
      return null;
    }
    const v = (o as Record<string, Object>)[key];
    if (v === null || v === undefined || !Array.isArray(v)) {
      return null;
    }
    return v as Array<Object>;
  }

  static str(o: Object | null, key: string): string | null {
    if (o === null) {
      return null;
    }
    const v = (o as Record<string, Object>)[key];
    if (typeof v === 'string') {
      return v as string;
    }
    return null;
  }

  static num(o: Object | null, key: string): number | null {
    if (o === null) {
      return null;
    }
    const v = (o as Record<string, Object>)[key];
    if (typeof v === 'number') {
      return v as number;
    }
    return null;
  }

  static bool(o: Object | null, key: string): boolean | null {
    if (o === null) {
      return null;
    }
    const v = (o as Record<string, Object>)[key];
    if (typeof v === 'boolean') {
      return v as boolean;
    }
    return null;
  }

  static strOr(o: Object | null, key: string, fallback: string): string {
    return Json.str(o, key) ?? fallback;
  }

  static numOr(o: Object | null, key: string, fallback: number): number {
    return Json.num(o, key) ?? fallback;
  }

  static parse(text: string): Object | null {
    try {
      const parsed = JSON.parse(text) as Object;
      return parsed;
    } catch (e) {
      return null;
    }
  }
}
