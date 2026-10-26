import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Prefs } from '../store/Prefs';

const SYSTEM = 'system';
const DARK = 'dark';
const LIGHT = 'light';

/**
 * Light / dark preference. The palette is entirely `sys.color.*`, so switching
 * here re-themes the whole app — including the system materials the tab bar and
 * title bar are drawn with.
 */
export class Appearance {
  private static context: common.UIAbilityContext | null = null;

  static attach(context: common.UIAbilityContext): void {
    Appearance.context = context;
  }

  static current(): string {
    return Prefs.getString(Prefs.keys.colorMode, SYSTEM);
  }

  static apply(mode: string): void {
    Prefs.putString(Prefs.keys.colorMode, mode);
    const ctx = Appearance.context;
    if (ctx === null) {
      return;
    }
    let value = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === DARK) {
      value = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (mode === LIGHT) {
      value = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    ctx.getApplicationContext().setColorMode(value);
  }

  /** Re-applies the stored preference on launch. */
  static restore(): void {
    Appearance.apply(Appearance.current());
  }

  static readonly options: Array<string> = [SYSTEM, DARK, LIGHT];
  static readonly labels: Array<string> = ['跟随系统', '深色', '浅色'];
}
