import { MdBlock, MdSpan, MarkdownParser } from '../core/markdown/MarkdownParser';
import { Theme } from '../core/ui/Theme';

/**
 * Renders assistant/user markdown as ArkUI components.
 *
 * Nothing here sets `width('100%')`: the bubble sizes to its content, so a
 * percentage width on a child would resolve against the parent's constraint
 * (its max) rather than its content box and spill past the bubble background.
 * Long unbroken tokens (paths, commands, JSON) are wrapped with BREAK_ALL.
 */
@Component
export struct MarkdownView {
  text: string = '';
  onOpenFile: (path: string) => void = () => {};

  private isStandaloneFile(block: MdBlock): boolean {
    if (block.spans.length !== 1) {
      return false;
    }
    const span = block.spans[0];
    if (span.kind !== 'code' && span.kind !== 'text') {
      return false;
    }
    return isFilePath(span.text);
  }

  @Builder
  InlineSpans(spans: Array<MdSpan>) {
    Text() {
      ForEach(spans, (span: MdSpan) => {
        if (span.kind === 'code') {
          Span(span.text)
            .fontFamily('monospace')
            .fontColor(Theme.code)
        } else if (span.kind === 'bold') {
          Span(span.text)
            .fontWeight(FontWeight.Bold)
        } else if (span.kind === 'italic') {
          Span(span.text)
            .fontStyle(FontStyle.Italic)
        } else if (span.kind === 'link') {
          Span(span.text)
            .fontColor(Theme.code)
            .decoration({ type: TextDecorationType.Underline, color: Theme.code })
        } else {
          Span(span.text)
        }
      }, (span: MdSpan, index: number) => `${index}:${span.kind}`)
    }
    .fontSize(Theme.fontBody)
    .lineHeight(22)
    .fontColor(Theme.text)
    .wordBreak(WordBreak.BREAK_ALL)
  }

  private headingSize(level: number): number {
    if (level <= 1) {
      return 18;
    }
    if (level === 2) {
      return 16;
    }
    return 15;
  }

  build() {
    Column({ space: 8 }) {
      ForEach(MarkdownParser.parse(this.text), (block: MdBlock) => {
        if (block.kind === 'heading') {
          Text() {
            ForEach(block.spans, (span: MdSpan) => {
              Span(span.text).fontWeight(FontWeight.Bold)
            }, (span: MdSpan, i: number) => `${i}`)
          }
          .fontSize(this.headingSize(block.level))
          .lineHeight(23)
          .fontColor(Theme.text)
          .wordBreak(WordBreak.BREAK_ALL)
        } else if (block.kind === 'code') {
          Column({ space: 6 }) {
            if (block.lang.length > 0) {
              Text(block.lang.toUpperCase())
                .fontSize(Theme.fontTiny)
                .fontColor(Theme.faint)
            }
            Text(block.code.length > 0 ? block.code : ' ')
              .fontSize(Theme.fontSmall)
              .lineHeight(19)
              .fontFamily('monospace')
              .fontColor(Theme.text)
              .wordBreak(WordBreak.BREAK_ALL)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor(Theme.bg)
          .border({ width: 1, color: Theme.border })
          .borderRadius(10)
        } else if (block.kind === 'list') {
          Row({ space: 8 }) {
            Text(block.marker)
              .fontSize(Theme.fontBody)
              .lineHeight(22)
              .fontColor(Theme.faint)
            this.InlineSpans(block.spans)
          }
          .alignItems(VerticalAlign.Top)
        } else if (block.kind === 'quote') {
          Column() {
            this.InlineSpans(block.spans)
          }
          .padding({ left: 10 })
          .border({ width: { left: 2 }, color: Theme.borderStrong })
          .alignItems(HorizontalAlign.Start)
        } else if (block.kind === 'hr') {
          Divider()
            .color(Theme.border)
            .width(80)
        } else if (this.isStandaloneFile(block)) {
          Text(block.spans[0].text)
            .fontSize(Theme.fontSmall)
            .fontFamily('monospace')
            .fontColor(Theme.code)
            .decoration({ type: TextDecorationType.Underline, color: Theme.code })
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(Theme.bg)
            .borderRadius(6)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .wordBreak(WordBreak.BREAK_ALL)
            .onClick(() => this.onOpenFile(block.spans[0].text))
        } else {
          this.InlineSpans(block.spans)
        }
      }, (block: MdBlock, index: number) => `${index}:${block.kind}`)
    }
    .alignItems(HorizontalAlign.Start)
  }
}

function isFilePath(text: string): boolean {
  if (text.length === 0 || text.indexOf(' ') >= 0 || text.indexOf('://') >= 0) {
    return false;
  }
  if (text.indexOf('/') < 0) {
    return false;
  }
  return /\.[A-Za-z0-9]+(:[0-9]+)?$/.test(text);
}
