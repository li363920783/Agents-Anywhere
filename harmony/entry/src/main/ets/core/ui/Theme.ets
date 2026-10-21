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
  /** Page sits on the *sub* background and cards on `card_bg`; both being white
   *  made the light theme read as one continuous sheet. */
  static readonly bg: Resource = $r('sys.color.ohos_id_color_sub_background');
  static readonly surface: Resource = $r('sys.color.ohos_id_color_card_bg');
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

  // Glow (光晕). Also untokenised. The tint is the emphasize blue (#007DFF in
  // both light and dark), so one set of values reads as a halo on either
  // theme — a white or black hairline would only work in one.
  static readonly halo: string = '#59007DFF';
  static readonly haloSoft: string = '#26007DFF';
  /** Ambient wash: centre alpha, then a fully transparent outer stop. */
  static readonly haloWash: string = '#2E007DFF';
  static readonly haloFade: string = '#00007DFF';

  /**
   * Status hues. The system palette has no success token — only `warning` and
   * `alert`, which both read as red — so these are hand-picked like the halo.
   * All mid-tone and saturated, so one value reads on light and on dark.
   */
  static readonly ok: string = '#FF2FB344';
  static readonly busy: string = '#FF007DFF';
  static readonly waiting: string = '#FFFF9F0A';
  static readonly stalled: string = '#FF8B5CF6';
  static readonly bad: string = '#FFFF3B30';
  static readonly neutral: string = '#FF8A8A8E';
  /** Idle gets its own muted slate, not `neutral`: most sessions are idle, and
   *  a list of grey chips is what "monotone" looked like. */
  static readonly idle: string = '#FF6E8CB8';

  /** 12% tint of a `#AARRGGBB` colour, for chip backgrounds. */
  static tint(color: string): string {
    return `#1F${color.substring(3)}`;
  }

  // Shape
  static readonly gutter: string = '92%';
  static readonly radiusCard: number = 14;
  static readonly radiusBubble: number = 14;
  static readonly radiusPill: number = 999;
  /** Bottom padding a scroll view needs so the floating tab bar clears it. */
  static readonly barClearance: number = 96;
}
