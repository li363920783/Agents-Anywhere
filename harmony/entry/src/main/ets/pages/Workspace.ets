import { ApiClient } from '../core/net/ApiClient';
import { ApiError } from '../core/net/ApiError';
import { Json } from '../core/util/Json';
import { TextFile } from '../core/model/Catalog';
import {
  FsEntry,
  FsListResult,
  FsPathRequest,
  ShellExecRequest,
  ShellExecResult
} from '../core/model/Workspace';
import { Theme } from '../core/ui/Theme';

/**
 * Workspace of the session's connector: browse the tree and run one-shot
 * commands in the session cwd. Backed by `/connectors/{id}/fs/*` and
 * `/shell/exec` — the connector has to be online for any of it.
 */
@Component
export struct Workspace {
  @Consume('rootStack') rootStack: NavPathStack;
  connectorId: string = '';
  root: string = '';
  title: string = '';

  @State tab: number = 0;

  @State path: string = '.';
  /** Previously visited directories, so "up" never escapes the workspace. */
  @State trail: Array<string> = [];
  @State entries: Array<FsEntry> = [];
  @State filesLoading: boolean = false;
  @State filesError: string = '';

  @State previewOpen: boolean = false;
  @State previewName: string = '';
  @State previewContent: string = '';
  @State previewBinary: boolean = false;
  @State previewError: string = '';

  @State command: string = '';
  @State output: string = '';
  @State running: boolean = false;

  aboutToAppear(): void {
    void this.loadDir('.');
  }

  private async loadDir(target: string): Promise<void> {
    if (this.connectorId.length === 0) {
      this.filesError = 'This session has no connector';
      return;
    }
    this.filesLoading = true;
    this.filesError = '';
    try {
      const body = new FsPathRequest();
      body.path = target;
      const res = await ApiClient.shared.post(
        `/connectors/${this.connectorId}/fs/list?root=${encodeURIComponent(this.root)}`,
        body
      );
      const list = FsListResult.fromJson(Json.obj(res, 'result'));
      this.entries = list.entries;
      this.path = list.path.length > 0 ? list.path : target;
    } catch (e) {
      const err = e as Error;
      this.filesError = err instanceof ApiError ? err.message : 'Cannot list this directory';
    } finally {
      this.filesLoading = false;
    }
  }

  private openEntry(entry: FsEntry): void {
    if (entry.isDirectory) {
      this.trail.push(this.path);
      void this.loadDir(entry.path);
      return;
    }
    void this.openFile(entry.path);
  }

  private up(): void {
    if (this.trail.length === 0) {
      return;
    }
    const previous = this.trail[this.trail.length - 1];
    this.trail = this.trail.slice(0, this.trail.length - 1);
    void this.loadDir(previous);
  }

  private async openFile(filePath: string): Promise<void> {
    const slash = filePath.lastIndexOf('/');
    this.previewName = slash >= 0 ? filePath.substring(slash + 1) : filePath;
    this.previewContent = '';
    this.previewError = '';
    this.previewBinary = false;
    this.previewOpen = true;
    try {
      const body = new FsPathRequest();
      body.path = filePath;
      const res = await ApiClient.shared.post(
        `/connectors/${this.connectorId}/fs/readText?root=${encodeURIComponent(this.root)}`,
        body
      );
      const file = TextFile.fromJson(res);
      if (file.name.length > 0) {
        this.previewName = file.name;
      }
      this.previewContent = file.content;
      this.previewBinary = file.binary;
    } catch (e) {
      const err = e as Error;
      this.previewError = err instanceof ApiError ? err.message : 'Cannot read this file';
    }
  }

  private async runCommand(): Promise<void> {
    const cmd = this.command.trim();
    if (cmd.length === 0 || this.running) {
      return;
    }
    this.running = true;
    try {
      const body = new ShellExecRequest();
      body.command = cmd;
      body.timeoutMs = 120000;
      const res = await ApiClient.shared.post(
        `/connectors/${this.connectorId}/shell/exec?root=${encodeURIComponent(this.root)}`,
        body
      );
      const out = ShellExecResult.fromJson(Json.obj(res, 'result'));
      const parts: Array<string> = [`$ ${cmd}`];
      if (out.stdout.length > 0) {
        parts.push(out.stdout);
      }
      if (out.stderr.length > 0) {
        parts.push(out.stderr);
      }
      parts.push(`[exit ${out.exitCode}]`);
      this.output = parts.join('\n');
      this.command = '';
    } catch (e) {
      const err = e as Error;
      const msg = err instanceof ApiError ? err.message : 'command failed';
      this.output = `$ ${cmd}\n${msg}`;
    } finally {
      this.running = false;
    }
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(18)
            .fontColor([Theme.text])
        }
        .width(34)
        .height(34)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.raised)
        .borderRadius(Theme.radiusPill)
        .onClick(() => this.rootStack.pop())
        Column({ space: 2 }) {
          Text(this.title.length > 0 ? this.title : 'Workspace')
            .fontSize(Theme.fontHeading)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.root)
            .fontSize(Theme.fontTiny)
            .fontFamily('monospace')
            .fontColor(Theme.faint)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width(Theme.gutter)
      .padding({ top: 10, bottom: 6 })

      Tabs({ index: this.tab }) {
        TabContent() {
          this.FilesTab()
        }
        .tabBar(this.TabLabel('文件', 0))

        TabContent() {
          this.CommandsTab()
        }
        .tabBar(this.TabLabel('命令', 1))
      }
      .barMode(BarMode.Fixed)
      .barHeight(44)
      .layoutWeight(1)
      .onChange((index: number) => {
        this.tab = index;
      })

      if (this.previewOpen) {
        this.PreviewSheet()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }

  @Builder
  TabLabel(label: string, index: number) {
    Column() {
      Text(label)
        .fontSize(Theme.fontSmall)
        .fontWeight(this.tab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.tab === index ? Theme.accent : Theme.faint)
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  FilesTab() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('..')
          .fontSize(Theme.fontSmall)
          .fontColor(this.trail.length > 0 ? Theme.text : Theme.faint)
          .width(40)
          .height(32)
          .textAlign(TextAlign.Center)
          .backgroundColor(Theme.raised)
          .borderRadius(8)
          .onClick(() => this.up())
        Text(this.path)
          .fontSize(Theme.fontTiny)
          .fontFamily('monospace')
          .fontColor(Theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Column() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(16)
            .fontColor([Theme.muted])
        }
        .width(40)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.raised)
        .borderRadius(8)
        .onClick(() => this.loadDir(this.path))
      }
      .width(Theme.gutter)

      if (this.filesError.length > 0) {
        Text(this.filesError)
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.danger)
          .width(Theme.gutter)
          .padding(8)
          .wordBreak(WordBreak.BREAK_ALL)
      }

      if (this.entries.length === 0 && !this.filesLoading) {
        Text('Empty directory')
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.faint)
          .margin({ top: 40 })
      } else {
        List({ space: 6 }) {
          ForEach(this.entries, (entry: FsEntry) => {
            ListItem() {
              Row({ space: 10 }) {
                Text(entry.isDirectory ? '📁' : '📄')
                  .fontSize(Theme.fontBody)
                Text(entry.name)
                  .fontSize(Theme.fontSmall)
                  .fontFamily('monospace')
                  .fontColor(entry.isDirectory ? Theme.text : Theme.muted)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (!entry.isDirectory && entry.size > 0) {
                  Text(`${entry.size}`)
                    .fontSize(Theme.fontTiny)
                    .fontColor(Theme.faint)
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor(Theme.surface)
              .borderRadius(8)
              .onClick(() => this.openEntry(entry))
            }
          }, (entry: FsEntry) => entry.path)
        }
        .width(Theme.gutter)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 8 })
  }

  @Builder
  CommandsTab() {
    Column({ space: 10 }) {
      Scroll() {
        Text(this.output.length > 0 ? this.output : '输出会显示在这里。命令在会话的工作目录执行。')
          .fontSize(Theme.fontTiny)
          .fontFamily('monospace')
          .lineHeight(18)
          .fontColor(this.output.length > 0 ? Theme.muted : Theme.faint)
          .width('100%')
          .padding(12)
          .wordBreak(WordBreak.BREAK_ALL)
      }
      .width(Theme.gutter)
      .layoutWeight(1)
      .backgroundColor(Theme.surface)
      .borderRadius(Theme.radiusCard)
      .align(Alignment.TopStart)

      Row({ space: 8 }) {
        TextInput({ placeholder: 'ls -la', text: this.command })
          .height(40)
          .layoutWeight(1)
          .fontSize(Theme.fontSmall)
          .fontFamily('monospace')
          .backgroundColor(Theme.surface)
          .fontColor(Theme.text)
          .caretColor(Theme.accent)
          .placeholderColor(Theme.faint)
          .border({ width: 1, color: Theme.border })
          .borderRadius(10)
          .onChange((v: string) => {
            this.command = v;
          })
          .onSubmit(() => {
            void this.runCommand();
          })
        Button(this.running ? '…' : 'Run')
          .height(40)
          .fontSize(Theme.fontSmall)
          .backgroundColor(this.running ? Theme.raised : Theme.accent)
          .fontColor(this.running ? Theme.muted : Theme.onAccent)
          .borderRadius(10)
          .onClick(() => {
            void this.runCommand();
          })
      }
      .width(Theme.gutter)
      .padding({ bottom: 8 })
    }
    .width('100%')
    .height('100%')
    .padding({ top: 10 })
  }

  @Builder
  PreviewSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.previewName)
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('关闭')
          .fontSize(Theme.fontTiny)
          .fontColor(Theme.accent)
          .onClick(() => {
            this.previewOpen = false;
          })
      }
      .width('100%')

      if (this.previewError.length > 0) {
        Text(this.previewError)
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.danger)
          .wordBreak(WordBreak.BREAK_ALL)
      } else if (this.previewBinary) {
        Text('二进制文件，暂不支持预览')
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.faint)
      } else {
        Scroll() {
          Text(this.previewContent)
            .fontSize(Theme.fontTiny)
            .fontFamily('monospace')
            .lineHeight(17)
            .fontColor(Theme.muted)
            .width('100%')
            .wordBreak(WordBreak.BREAK_ALL)
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .height('55%')
    .padding(14)
    .backgroundColor(Theme.raised)
    .border({ width: 1, color: Theme.border })
    .borderRadius(Theme.radiusCard)
  }
}
