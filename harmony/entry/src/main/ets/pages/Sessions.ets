import { promptAction } from '@kit.ArkUI';
import { SessionDetailParam } from '../core/model/Nav';
import { ApiClient } from '../core/net/ApiClient';
import { ApiError } from '../core/net/ApiError';
import { Fmt } from '../core/util/Fmt';
import { SessionListResponse, SessionView } from '../core/model/Session';
import { BulkActionRequest, SessionMetaPatch } from '../core/model/Bodies';
import { ConnectorListResponse, ConnectorView } from '../core/model/Connector';
import { Theme } from '../core/ui/Theme';

/** One project section in the session list. */
class ProjectGroup {
  name: string = '';
  /** Newest activity in the group, used to order sections. */
  latest: string = '';
  items: Array<SessionView> = [];
}

/**
 * Project a session belongs to: the repository root, with a Claude Code
 * worktree path (`…/<repo>/.claude/worktrees/<name>`) folded back to `<repo>`.
 */
function projectName(cwd: string | null): string {
  if (cwd === null || cwd.length === 0) {
    return 'Unknown';
  }
  const marker = '/.claude/worktrees/';
  const idx = cwd.indexOf(marker);
  const root = idx >= 0 ? cwd.substring(0, idx) : cwd;
  const parts = root.split(/[\\/]/).filter((p: string) => p.length > 0);
  return parts.length > 0 ? parts[parts.length - 1] : root;
}

/** Leaf directory of a session's cwd — the worktree (or checkout) name. */
function worktreeName(cwd: string | null): string {
  const path = cwd ?? '';
  const parts = path.split(/[\\/]/).filter((p: string) => p.length > 0);
  return parts.length > 0 ? parts[parts.length - 1] : path;
}

/**
 * `--resume` / compaction injects a whole prior transcript as the first user
 * message; those sessions are titled after that preamble and are noise in a
 * session list.
 */
function isResumeLog(title: string | null): boolean {
  const t = (title ?? '').trim().toLowerCase();
  return t.startsWith('below is a conversation log') || t.startsWith('以下是一段来自');
}

@Component
export struct Sessions {
  @Consume('rootStack') rootStack: NavPathStack;
  @State archived: boolean = false;
  @State items: Array<SessionView> = [];
  @State groups: Array<ProjectGroup> = [];
  @State connectors: Array<ConnectorView> = [];
  @State deviceFilter: string = '';
  @State hideLogs: boolean = true;
  @State hiddenLogCount: number = 0;
  @State refreshing: boolean = false;
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State query: string = '';
  /** Names of project sections the user collapsed. */
  @State collapsed: Array<string> = [];

  private isCollapsed(name: string): boolean {
    return this.collapsed.indexOf(name) >= 0;
  }

  private toggleGroup(name: string): void {
    const next: Array<string> = [];
    let removed = false;
    for (let i = 0; i < this.collapsed.length; i++) {
      if (this.collapsed[i] === name) {
        removed = true;
        continue;
      }
      next.push(this.collapsed[i]);
    }
    if (!removed) {
      next.push(name);
    }
    this.collapsed = next;
  }

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      // `GET /sessions` is the paginated list; `/sessions/list` is the unpaginated
      // workspace inventory and ignores `limit`.
      const res = await ApiClient.shared.get(
        `/sessions?archived=${this.archived}&limit=100`
      );
      const rows = SessionListResponse.fromJson(res).sessions;
      rows.sort((a: SessionView, b: SessionView) => {
        if (a.pinned !== b.pinned) {
          return a.pinned ? -1 : 1;
        }
        const av = (a.lastActivityAt ?? a.lastItemAt ?? '');
        const bv = (b.lastActivityAt ?? b.lastItemAt ?? '');
        return av < bv ? 1 : -1;
      });
      this.items = rows;
      await this.loadConnectors();
      this.applyFilter();
    } catch (e) {
      const err = e as Error;
      const msg = err instanceof ApiError ? err.message : 'load failed';
      this.errorMsg = msg;
    } finally {
      this.loading = false;
    }
  }

  /** Device chips are best-effort: a failure just leaves "All devices" alone. */
  private async loadConnectors(): Promise<void> {
    try {
      const res = await ApiClient.shared.get('/connectors');
      this.connectors = ConnectorListResponse.fromJson(res).connectors;
    } catch (e) {
      this.connectors = [];
    }
  }

  private matches(item: SessionView, q: string): boolean {
    const haystack = [
      item.title ?? '',
      worktreeName(item.cwd),
      projectName(item.cwd),
      item.cwd ?? '',
      item.gitBranch ?? '',
      item.runtime
    ].join('\n').toLowerCase();
    return haystack.includes(q);
  }

  /**
   * Rebuilds the grouped list from the query + device filter. Kept out of
   * `build()` so a 500-session list is not regrouped on every render.
   * ponytail: linear group scan — fine for ~100 projects, revisit if it grows.
   */
  private applyFilter(): void {
    const q = this.query.trim().toLowerCase();
    const groups: Array<ProjectGroup> = [];
    let hidden = 0;
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      if (this.deviceFilter.length > 0 && item.connectorId !== this.deviceFilter) {
        continue;
      }
      if (isResumeLog(item.title)) {
        hidden++;
        if (this.hideLogs) {
          continue;
        }
      }
      if (q.length > 0 && !this.matches(item, q)) {
        continue;
      }
      const name = projectName(item.cwd);
      let group: ProjectGroup | null = null;
      for (let j = 0; j < groups.length; j++) {
        if (groups[j].name === name) {
          group = groups[j];
          break;
        }
      }
      if (group === null) {
        group = new ProjectGroup();
        group.name = name;
        groups.push(group);
      }
      group.items.push(item);
      const at = item.lastActivityAt ?? item.lastItemAt ?? '';
      if (at > group.latest) {
        group.latest = at;
      }
    }
    groups.sort((a: ProjectGroup, b: ProjectGroup) => (a.latest < b.latest ? 1 : -1));
    this.hiddenLogCount = hidden;
    this.groups = groups;
  }

  private totalShown(): number {
    let n = 0;
    for (let i = 0; i < this.groups.length; i++) {
      n += this.groups[i].items.length;
    }
    return n;
  }

  private async bulk(path: string, ids: string[]): Promise<void> {
    try {
      const body = new BulkActionRequest();
      body.sessionIds = ids;
      await ApiClient.shared.post(path, body);
      await this.load();
    } catch (e) {
      const err = e as Error;
      promptAction.showToast({ message: err instanceof ApiError ? err.message : 'action failed', duration: 1500 });
    }
  }

  private async patchMeta(id: string, patch: SessionMetaPatch): Promise<void> {
    try {
      await ApiClient.shared.patch(`/sessions/${id}/meta`, patch);
      await this.load();
    } catch (e) {
      const err = e as Error;
      promptAction.showToast({ message: err instanceof ApiError ? err.message : 'patch failed', duration: 1500 });
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('Sessions')
          .fontSize(Theme.fontTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .layoutWeight(1)
        Button(this.archived ? 'Archived' : 'Active')
          .fontSize(Theme.fontTiny)
          .height(30)
          .backgroundColor(Theme.raised)
          .fontColor(this.archived ? Theme.muted : Theme.accent)
          .border({ width: 1, color: this.archived ? Theme.border : Theme.accent })
          .borderRadius(Theme.radiusPill)
          .onClick(() => {
            this.archived = !this.archived;
            void this.load();
          })
      }
      .width(Theme.gutter)
      .padding({ top: 12, bottom: 10 })

      TextInput({ placeholder: 'Search sessions, worktrees, projects…', text: this.query })
        .height(40)
        .width(Theme.gutter)
        .fontSize(Theme.fontSmall)
        .backgroundColor(Theme.surface)
        .fontColor(Theme.text)
        .caretColor(Theme.accent)
        .placeholderColor(Theme.faint)
        .border({ width: 1, color: Theme.border })
        .borderRadius(10)
        .onChange((v: string) => {
          this.query = v;
          this.applyFilter();
        })

      Scroll() {
        Row({ space: 8 }) {
          if (this.connectors.length > 1) {
            this.DeviceChip('All devices', '')
            ForEach(this.connectors, (c: ConnectorView) => {
              this.DeviceChip(c.name, c.id)
            }, (c: ConnectorView) => c.id)
          }
          if (this.hiddenLogCount > 0) {
            this.LogChip()
          }
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width(Theme.gutter)
      .padding({ top: 10 })

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.danger)
          .width(Theme.gutter)
          .padding(8)
          .wordBreak(WordBreak.BREAK_ALL)
      }

      if (this.groups.length === 0 && !this.loading) {
        Column() {
          Text(this.query.trim().length > 0
            ? `No sessions match “${this.query.trim()}”`
            : (this.archived ? 'No archived sessions' : 'No active sessions'))
            .fontSize(Theme.fontSmall)
            .fontColor(Theme.faint)
            .margin({ top: 60 })
        }
        .layoutWeight(1)
      } else {
        Column() {
          Refresh({ refreshing: $$this.refreshing }) {
            List({ space: 10 }) {
              ForEach(this.groups, (group: ProjectGroup) => {
                // The header is a plain ListItem rather than a ListItemGroup
                // header: a ListItemGroup header did not receive taps here, and
                // its key carries the collapsed flag so ArkUI re-runs the branch
                // (a ForEach branch is only re-evaluated when its key changes).
                ListItem() {
                  this.GroupHeader(group.name, group.items.length, this.isCollapsed(group.name))
                }
                if (!this.isCollapsed(group.name)) {
                  ForEach(group.items, (item: SessionView) => {
                    ListItem() {
                      this.SessionRow(item, group.name)
                    }
                    .swipeAction({
                      end: {
                        builder: () => {
                          this.SwipePin(item)
                        }
                      }
                    })
                  }, (item: SessionView) => `${item.id}-${item.updatedSeq}-${item.pinned}-${item.archived}`)
                }
              }, (group: ProjectGroup) => `${group.name}-${this.isCollapsed(group.name) ? 1 : 0}`)
            }
            .width(Theme.gutter)
            .layoutWeight(1)
          }
          .onRefreshing(() => {
            void this.load().then(() => {
              this.refreshing = false;
            });
          })
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }

  @Builder
  DeviceChip(label: string, id: string) {
    Text(label)
      .fontSize(Theme.fontTiny)
      .fontColor(this.deviceFilter === id ? Theme.accent : Theme.muted)
      .backgroundColor(Theme.raised)
      .border({ width: 1, color: this.deviceFilter === id ? Theme.accent : Theme.border })
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(Theme.radiusPill)
      .maxLines(1)
      .onClick(() => {
        this.deviceFilter = id;
        this.applyFilter();
      })
  }

  @Builder
  LogChip() {
    Text(this.hideLogs ? `Hiding ${this.hiddenLogCount} logs` : `Showing ${this.hiddenLogCount} logs`)
      .fontSize(Theme.fontTiny)
      .fontColor(this.hideLogs ? Theme.muted : Theme.warn)
      .backgroundColor(Theme.raised)
      .border({ width: 1, color: this.hideLogs ? Theme.border : Theme.warn })
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(Theme.radiusPill)
      .maxLines(1)
      .onClick(() => {
        this.hideLogs = !this.hideLogs;
        this.applyFilter();
      })
  }

  @Builder
  GroupHeader(name: string, count: number, collapsed: boolean) {
    Row({ space: 8 }) {
      Row()
        .width(7)
        .height(7)
        .border({ width: { bottom: 1.5, right: 1.5 }, color: Theme.muted })
        .rotate({ angle: collapsed ? -45 : 45 })
        .margin({ left: 2, right: 2 })
      Text(name)
        .fontSize(Theme.fontTiny)
        .fontColor(Theme.muted)
        .fontFamily('monospace')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(`${count}`)
        .fontSize(Theme.fontTiny)
        .fontColor(Theme.faint)
    }
    .width('100%')
    .padding({ top: 16, bottom: 8 })
    .backgroundColor(Theme.bg)
    .onClick(() => this.toggleGroup(name))
  }

  @Builder
  SessionRow(item: SessionView, project: string) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Circle({ width: 7, height: 7 })
          .fill(Fmt.statusColor(item.status))
          .margin({ top: 6 })
        Text(item.title ?? item.cwd ?? '(' + item.runtime + ' session)')
          .fontSize(Theme.fontBody)
          .lineHeight(19)
          .fontColor(Theme.text)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (item.pinned) {
          Text('PIN')
            .fontSize(9)
            .fontColor(Theme.warn)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .border({ width: 1, color: Theme.warn })
            .borderRadius(4)
        }
        if (item.unread) {
          Circle({ width: 7, height: 7 }).fill(Theme.accent)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row({ space: 6 }) {
        // The group header already names the project; only show a distinct worktree.
        if (item.cwd && worktreeName(item.cwd) !== project) {
          Text(worktreeName(item.cwd))
            .fontSize(Theme.fontTiny)
            .fontColor(Theme.muted)
            .fontFamily('monospace')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        } else {
          Blank().layoutWeight(1)
        }
        Text(Fmt.relTime(item.lastActivityAt ?? item.lastItemAt, Date.now()))
          .fontSize(Theme.fontTiny)
          .fontColor(Theme.faint)
      }
      .width('100%')

      Row({ space: 6 }) {
        Text(item.runtime)
          .fontSize(Theme.fontTiny)
          .fontColor(Theme.faint)
        Text('·').fontSize(Theme.fontTiny).fontColor(Theme.borderStrong)
        Text(item.connectorStatus === 'online' ? 'online' : 'offline')
          .fontSize(Theme.fontTiny)
          .fontColor(item.connectorStatus === 'online' ? Theme.accent : Theme.faint)
        Text('·').fontSize(Theme.fontTiny).fontColor(Theme.borderStrong)
        Text(Fmt.statusLabel(item.status))
          .fontSize(Theme.fontTiny)
          .fontColor(Fmt.statusColor(item.status))
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.border })
    .borderRadius(Theme.radiusCard)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      const param = new SessionDetailParam();
      param.id = item.id;
      this.rootStack.pushPath(new NavPathInfo('SessionDetail', param));
    })
  }

  @Builder
  SwipePin(item: SessionView) {
    Button(item.pinned ? 'Unpin' : 'Pin')
      .fontSize(Theme.fontSmall)
      .height(48)
      .backgroundColor(Theme.raised)
      .fontColor(Theme.text)
      .onClick(() => {
        const patch = new SessionMetaPatch();
        patch.pinned = !item.pinned;
        void this.patchMeta(item.id, patch);
      })
  }
}
