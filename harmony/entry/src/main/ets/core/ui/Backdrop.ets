import { Theme } from './Theme';

/**
 * Ambient light layer (光效装饰层). Sits behind page content, so the gutters
 * between cards carry a soft coloured glow — and, just as importantly, the
 * floating tab bar's system material has something with structure to blur.
 * A flat background is why the frosted bar read as a solid strip.
 *
 * The wash is a `radialGradient` that fades to a transparent stop, not a
 * filled disc softened with `.blur()`: `blur` blurs a component's *content*,
 * so a background-only shape keeps a hard circular edge. The radial falloff is
 * inherently soft, and costs no extra render pass.
 *
 * Two discs only, and they never animate.
 */
@Component
export struct Backdrop {
  build() {
    Stack() {
      // Base, so the layer is self-sufficient wherever it is dropped.
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.bg)

      // Accent light bleeding in from the top-left, behind the header.
      Column()
        .width(340)
        .height(340)
        .borderRadius(170)
        .position({ x: -130, y: -150 })
        .radialGradient({
          center: ['50%', '50%'],
          radius: 170,
          colors: [[Theme.haloWash, 0.0], [Theme.haloFade, 1.0]]
        })

      // Counter-glow low on the screen, so cards fade into the floating bar.
      Column()
        .width(280)
        .height(280)
        .borderRadius(140)
        .position({ x: '55%', y: '64%' })
        .radialGradient({
          center: ['50%', '50%'],
          radius: 140,
          colors: [[Theme.haloWash, 0.0], [Theme.haloFade, 1.0]]
        })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
