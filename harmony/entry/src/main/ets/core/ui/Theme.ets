/**
 * Design tokens for the HarmonyOS client.
 *
 * "Slate, desaturated": near-black blue-grey surfaces, low-emission text and a
 * single muted accent. Buttons are outlined by default; only the primary action
 * of a screen is filled. Every screen reads from here instead of hardcoding hex.
 */
export class Theme {
  // Surfaces
  static readonly bg: string = '#0F1419';
  static readonly surface: string = '#1A2129';
  static readonly raised: string = '#222A33';
  static readonly border: string = '#2A333D';
  static readonly borderStrong: string = '#3A4552';

  // Text
  static readonly text: string = '#E6EDF3';
  static readonly muted: string = '#8B98A5';
  static readonly faint: string = '#6B7684';

  // Accents
  static readonly accent: string = '#3FB950';
  static readonly onAccent: string = '#0B1F10';
  static readonly user: string = '#2C5A8C';
  static readonly userText: string = '#E8F0FA';
  static readonly danger: string = '#E5534B';
  static readonly dangerSurface: string = '#2A1719';
  static readonly warn: string = '#D29922';
  static readonly code: string = '#79C0FF';

  // Type scale
  static readonly fontTitle: number = 22;
  static readonly fontHeading: number = 16;
  static readonly fontBody: number = 14;
  static readonly fontSmall: number = 12;
  static readonly fontTiny: number = 11;

  // Shape
  static readonly gutter: string = '92%';
  static readonly radiusCard: number = 12;
  static readonly radiusBubble: number = 14;
  static readonly radiusPill: number = 999;
}
