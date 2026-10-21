/**
 * Design tokens for the HarmonyOS client, expressed as system resources.
 *
 * Hex was a mistake here: a forced-dark palette fights every system surface.
 * The tab bar, title bar and materials all follow the *system* theme, so on a
 * light-mode device a hand-painted dark UI is framed by pale chrome — and a
 * system material renders light underneath white labels.
 *
 * Reading `sys.color.*` means the app simply follows light/dark, and system
 * materials blend instead of clashing.
 */
export class Theme {
  // Surfaces
  static readonly bg: Resource = $r('sys.color.ohos_id_color_background');
  static readonly surface: Resource = $r('sys.color.ohos_id_color_sub_background');
  static readonly raised: Resource = $r('sys.color.ohos_id_color_text_field_bg');
  static readonly border: Resource = $r('sys.color.ohos_id_color_list_separator');
  static readonly borderStrong: Resource = $r('sys.color.ohos_id_color_tertiary');

  // Text
  static readonly text: Resource = $r('sys.color.ohos_id_color_primary');
  static readonly muted: Resource = $r('sys.color.ohos_id_color_secondary');
  static readonly faint: Resource = $r('sys.color.ohos_id_color_tertiary');

  // Accents
  static readonly accent: Resource = $r('sys.color.ohos_id_color_emphasize');
  /** Text/icons drawn on top of a filled accent surface. */
  static readonly onAccent: Resource = $r('sys.color.ohos_id_color_foreground_contrary');
  static readonly user: Resource = $r('sys.color.ohos_id_color_emphasize');
  static readonly userText: Resource = $r('sys.color.ohos_id_color_foreground_contrary');
  static readonly danger: Resource = $r('sys.color.ohos_id_color_alert');
  static readonly dangerSurface: Resource = $r('sys.color.ohos_id_color_sub_background');
  static readonly warn: Resource = $r('sys.color.ohos_id_color_warning');
  static readonly code: Resource = $r('sys.color.ohos_id_color_emphasize');

  // Type scale
  static readonly fontTitle: number = 22;
  static readonly fontHeading: number = 16;
  static readonly fontBody: number = 14;
  static readonly fontSmall: number = 12;
  static readonly fontTiny: number = 11;

  // Spacing scale (4pt grid) — keeps rhythm consistent instead of ad-hoc numbers
  static readonly spaceXs: number = 4;
  static readonly spaceSm: number = 8;
  static readonly spaceMd: number = 12;
  static readonly spaceLg: number = 16;
  static readonly spaceXl: number = 24;

  // Depth — a shadow is the one thing the system has no token for.
  static readonly shadow: string = '#33000000';

  // Shape
  static readonly gutter: string = '92%';
  static readonly radiusCard: number = 14;
  static readonly radiusBubble: number = 14;
  static readonly radiusPill: number = 999;
}
