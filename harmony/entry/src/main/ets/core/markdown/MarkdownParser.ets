/**
 * Lightweight Markdown parser for the HarmonyOS timeline.
 *
 * Supports: headings, paragraphs, fenced code blocks, bullet/ordered lists,
 * blockquotes, thematic breaks, and inline code / bold / italic / links.
 * Rendering lives in `ui/MarkdownView.ets`; this file is pure parsing.
 */

export class MdSpan {
  kind: string = 'text'; // text | code | bold | italic | link
  text: string = '';
  href: string = '';

  constructor(kind: string, text: string, href: string = '') {
    this.kind = kind;
    this.text = text;
    this.href = href;
  }
}

export class MdBlock {
  kind: string = 'paragraph'; // paragraph | heading | code | list | quote | hr
  level: number = 0;
  lang: string = '';
  ordered: boolean = false;
  marker: string = '';
  code: string = '';
  spans: Array<MdSpan> = [];

  constructor(kind: string) {
    this.kind = kind;
  }
}

export class MarkdownParser {
  static parse(markdown: string): Array<MdBlock> {
    const source = markdown.length === 0 ? '_(no content)_' : markdown;
    const lines: Array<string> = source.split('\n');
    const blocks: Array<MdBlock> = [];
    let i = 0;
    let paragraph: Array<string> = [];

    const flushParagraph = (): void => {
      if (paragraph.length === 0) {
        return;
      }
      const text = paragraph.join('\n').trim();
      paragraph = [];
      if (text.length === 0) {
        return;
      }
      const block = new MdBlock('paragraph');
      block.spans = MarkdownParser.parseInline(text);
      blocks.push(block);
    };

    while (i < lines.length) {
      const raw = lines[i];
      const line = raw.trimEnd();

      // Fenced code block
      if (/^\s*```/.test(line)) {
        flushParagraph();
        const lang = line.replace(/^\s*```/, '').trim();
        const body: Array<string> = [];
        i += 1;
        while (i < lines.length && !/^\s*```/.test(lines[i])) {
          body.push(lines[i]);
          i += 1;
        }
        if (i < lines.length) {
          i += 1; // closing fence
        }
        const block = new MdBlock('code');
        block.lang = lang;
        block.code = body.join('\n');
        blocks.push(block);
        continue;
      }

      // Thematic break
      if (/^\s*([-*_])\s*(\1\s*){2,}$/.test(line)) {
        flushParagraph();
        blocks.push(new MdBlock('hr'));
        i += 1;
        continue;
      }

      // Heading
      const heading = /^\s*(#{1,6})\s+(.*)$/.exec(line);
      if (heading !== null) {
        flushParagraph();
        const block = new MdBlock('heading');
        block.level = heading[1].length;
        block.spans = MarkdownParser.parseInline(heading[2].trim());
        blocks.push(block);
        i += 1;
        continue;
      }

      // Blockquote
      if (/^\s*>\s?/.test(line)) {
        flushParagraph();
        const body: Array<string> = [];
        while (i < lines.length && /^\s*>\s?/.test(lines[i])) {
          body.push(lines[i].replace(/^\s*>\s?/, ''));
          i += 1;
        }
        const block = new MdBlock('quote');
        block.spans = MarkdownParser.parseInline(body.join('\n').trim());
        blocks.push(block);
        continue;
      }

      // List item
      const bullet = /^\s*[-*+]\s+(.*)$/.exec(line);
      const ordered = /^\s*(\d+)[.)]\s+(.*)$/.exec(line);
      if (bullet !== null || ordered !== null) {
        flushParagraph();
        const block = new MdBlock('list');
        if (ordered !== null) {
          block.ordered = true;
          block.marker = `${ordered[1]}.`;
          block.spans = MarkdownParser.parseInline(ordered[2].trim());
        } else if (bullet !== null) {
          block.ordered = false;
          block.marker = '•';
          block.spans = MarkdownParser.parseInline(bullet[1].trim());
        }
        blocks.push(block);
        i += 1;
        continue;
      }

      // Blank line ends a paragraph
      if (line.trim().length === 0) {
        flushParagraph();
        i += 1;
        continue;
      }

      paragraph.push(line);
      i += 1;
    }

    flushParagraph();
    return blocks;
  }

  static parseInline(text: string): Array<MdSpan> {
    const spans: Array<MdSpan> = [];
    let buffer = '';
    let i = 0;

    const flush = (): void => {
      if (buffer.length > 0) {
        spans.push(new MdSpan('text', buffer));
        buffer = '';
      }
    };

    while (i < text.length) {
      const ch = text.charAt(i);

      // Inline code
      if (ch === '`') {
        flush();
        const end = text.indexOf('`', i + 1);
        if (end > i) {
          spans.push(new MdSpan('code', text.substring(i + 1, end)));
          i = end + 1;
          continue;
        }
      }

      // Bold **text**
      if (ch === '*' && text.charAt(i + 1) === '*') {
        flush();
        const end = text.indexOf('**', i + 2);
        if (end > i) {
          spans.push(new MdSpan('bold', text.substring(i + 2, end)));
          i = end + 2;
          continue;
        }
      }

      // Italic *text* or _text_
      if (ch === '*' || ch === '_') {
        flush();
        const end = text.indexOf(ch, i + 1);
        if (end > i) {
          spans.push(new MdSpan('italic', text.substring(i + 1, end)));
          i = end + 1;
          continue;
        }
      }

      // Link [text](url)
      if (ch === '[') {
        const close = text.indexOf(']', i + 1);
        if (close > i && text.charAt(close + 1) === '(') {
          const paren = text.indexOf(')', close + 2);
          if (paren > close) {
            flush();
            spans.push(new MdSpan(
              'link',
              text.substring(i + 1, close),
              text.substring(close + 2, paren),
            ));
            i = paren + 1;
            continue;
          }
        }
      }

      buffer += ch;
      i += 1;
    }

    flush();
    return spans;
  }
}
