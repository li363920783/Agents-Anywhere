import { Theme } from './Theme';

/**
 * Status dot. The colour carries the state, and `pulse` marks the states that
 * are still changing.
 *
 * The animation deliberately lives in this leaf component: a `@State` change
 * rebuilds the whole `build()` of whichever component owns it, so running this
 * loop up in the session list would rebuild the entire list every frame — and
 * that list has no pagination.
 */
@Component
export struct StatusDot {
  @Prop color: string = Theme.neutral;
  /** Watched: a session can go idle -> running while the row is on screen. */
  @Prop @Watch('onPulseChanged') pulse: boolean = false;
  /** Not `size`: that collides with `CustomComponent.size()`. */
  @Prop diameter: number = 7;
  @State glow: number = 1;
  private pulsing: boolean = false;

  aboutToAppear(): void {
    // @Watch does not fire for the initial value.
    this.onPulseChanged();
  }

  private onPulseChanged(): void {
    if (this.pulse === this.pulsing) {
      return;
    }
    this.pulsing = this.pulse;
    if (this.pulse) {
      animateTo({
        duration: 900,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      }, () => {
        this.glow = 0.2;
      });
    } else {
      // Settle back to solid rather than freezing mid-pulse.
      animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
        this.glow = 1;
      });
    }
  }

  build() {
    Circle({ width: this.diameter, height: this.diameter })
      .fill(this.color)
      .opacity(this.glow)
      .shadow({ radius: 6, color: this.color, offsetX: 0, offsetY: 0 })
  }
}

/**
 * A status pill: tinted background with a matching label. A chip rather than
 * tinted text, so the state is legible while scanning rather than only on
 * close reading.
 */
@Component
export struct StatusChip {
  @Prop label: string = '';
  @Prop color: string = Theme.neutral;

  build() {
    Text(this.label)
      .fontSize(Theme.fontTiny)
      .fontColor(this.color)
      .maxLines(1)
      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
      .backgroundColor(Theme.tint(this.color))
      .borderRadius(Theme.radiusPill)
  }
}
