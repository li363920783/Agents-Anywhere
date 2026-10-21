import { promptAction } from '@kit.ArkUI';
import { SessionDetailParam } from '../core/model/Nav';
import { ApiClient } from '../core/net/ApiClient';
import { ApiError } from '../core/net/ApiError';
import { DashboardWatcher, SESSIONS_KEY, UNREAD_KEY } from '../core/net/DashboardWatcher';
import { Fmt } from '../core/util/Fmt';
import { SessionView } from '../core/model/Session';
import { SessionMetaPatch, CreateAndStartRequest } from '../core/model/Bodies';
import { Json } from '../core/util/Json';
import { ConnectorListResponse, ConnectorView } from '../core/model/Connector';
import { Theme } from '../core/ui/Theme';
import { StatusChip, StatusDot } from '../core/ui/Status';

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

/** Statuses that mean the agent is working right now. */
const LIVE_STATUSES: Array<string> = ['running', 'pending', 'stopping', 'waiting'];

@Component
export struct Sessions {
  @Consume('rootStack') rootStack: NavPathStack;
  /**
   * The whole workspace inventory, pushed by the dashboard socket. The paged
   * `/sessions` endpoint only ever delivered the first 100 rows; the inventory
   * is unpaginated and includes archived sessions, so it backs both tabs.
   */
  @StorageLink(SESSIONS_KEY) @Watch('onSessionsChanged') all: Array<SessionView> = [];
  /** Unread count pushed alongside the inventory; also drives the launcher badge. */
  @StorageLink(UNREAD_KEY) unread: number = 0;
  @State archived: boolean = false;
  @State groups: Array<ProjectGroup> = [];
  @State connectors: Array<ConnectorView> = [];
  @State deviceFilter: string = '';
  /** '' = all; otherwise 'unread' | 'live' | 'attention'. */
  @State statusFilter: string = '';
  @State hideLogs: boolean = true;
  @State hiddenLogCount: number = 0;
  @State loading: boolean = true;
  @State query: string = '';
  /** Names of project sections the user collapsed. */
  @State collapsed: Array<string> = [];
  /** Drives the staggered entrance; flipped once, after the first rows exist. */
  @State revealed: boolean = false;
  /** Session under the finger, for the press-scale. */
  @State pressedId: string = '';
  /** Y of the skeleton's sweeping highlight. */
  @State sweep: number = -140;
  /** New-session composer, opened from a project header. */
  @State composing: boolean = false;
  @State creating: boolean = false;
  @State newGroupName: string = '';
  @State newConnectorId: string = '';
  @State newProjectId: string = '';
  @State newRuntime: string = '';
  @State newDraft: string = '';
  private revealTimer: number = -1;

  /**
   * Plays the entrance once. Deferred a frame so the cards animate *from* their
   * initial state — flipping it in the same frame they are built would just
   * render them already-revealed.
   */
  private scheduleReveal(): void {
    if (this.revealed || this.revealTimer !== -1) {
      return;
    }
    this.revealTimer = setTimeout(() => {
      this.revealTimer = -1;
      this.revealed = true;
    }, 60);
  }

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

  onSessionsChanged(): void {
    this.loading = false;
    this.applyFilter();
    this.scheduleReveal();
  }

  async aboutToAppear(): Promise<void> {
    // The socket is the list's only source, so make sure it is up even if the
    // ability did not start it (sign-in after launch, or a dropped connection).
    DashboardWatcher.shared.start();
    if (this.all.length > 0) {
      this.loading = false;
    }
    await this.loadConnectors();
    this.applyFilter();
    this.scheduleReveal();
    // The skeleton's highlight sweeps down and restarts. Only runs while the
    // list is loading, and it is the one animated element on screen then.
    animateTo({ duration: 1100, curve: Curve.Linear, iterations: -1 }, () => {
      this.sweep = 560;
    });
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

  /** Status facet. Kept beside the device filter so both narrow the same pass. */
  private matchesStatus(item: SessionView): boolean {
    if (this.statusFilter === 'unread') {
      return item.unread;
    }
    if (this.statusFilter === 'live') {
      return LIVE_STATUSES.indexOf(item.status) >= 0;
    }
    if (this.statusFilter === 'attention') {
      return item.status === 'waiting_approval';
    }
    return true;
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
    for (let i = 0; i < this.all.length; i++) {
      const item = this.all[i];
      if (item.archived !== this.archived) {
        continue;
      }
      if (this.deviceFilter.length > 0 && item.connectorId !== this.deviceFilter) {
        continue;
      }
      if (this.statusFilter.length > 0 && !this.matchesStatus(item)) {
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

  /** The unread chip is a shortcut to whatever is still unread. */
  private openFirstUnread(): void {
    let fallback: SessionView | null = null;
    for (let i = 0; i < this.all.length; i++) {
      const item = this.all[i];
      if (!item.unread) {
        continue;
      }
      if (!item.archived) {
        this.openSession(item.id);
        return;
      }
      if (fallback === null) {
        fallback = item;
      }
    }
    if (fallback !== null) {
      this.openSession(fallback.id);
    }
  }

  private openSession(id: string): void {
    const param = new SessionDetailParam();
    param.id = id;
    this.rootStack.pushPath(new NavPathInfo('SessionDetail', param));
  }

  /**
   * Resolves what a new session needs from a row already in the group. The list
   * groups by a derived project *name*, so the ids have to come from a real
   * session — the group itself only knows the name.
   */
  private startCompose(group: ProjectGroup): void {
    let seed: SessionView | null = null;
    for (let i = 0; i < group.items.length; i++) {
      const candidate = group.items[i];
      const pid = candidate.projectId;
      if (pid !== null && pid.length > 0) {
        seed = candidate;
        break;
      }
    }
    if (seed === null) {
      promptAction.showToast({
        message: '这个项目没有可用的 projectId，无法新建会话',
        duration: 2000
      });
      return;
    }
    this.newGroupName = group.name;
    this.newConnectorId = seed.connectorId;
    this.newProjectId = seed.projectId ?? '';
    this.newRuntime = seed.runtime;
    this.newDraft = '';
    this.composing = true;
  }

  private async createAndStart(): Promise<void> {
    const content = this.newDraft.trim();
    if (content.length === 0 || this.creating) {
      return;
    }
    this.creating = true;
    try {
      const body = new CreateAndStartRequest();
      body.connectorId = this.newConnectorId;
      body.projectId = this.newProjectId;
      body.runtime = this.newRuntime;
      body.content = content;
      const res = await ApiClient.shared.post('/sessions/create-and-start', body);
      const created = SessionView.fromJson(Json.obj(res, 'session'));
      this.composing = false;
      this.newDraft = '';
      if (created.id.length > 0) {
        this.openSession(created.id);
      }
    } catch (e) {
      const err = e as Error;
      promptAction.showToast({
        message: err instanceof ApiError ? err.message : 'create failed',
        duration: 2000
      });
    } finally {
      this.creating = false;
    }
  }

  /** The dashboard socket pushes a fresh snapshot after every meta change. */
  private async patchMeta(id: string, patch: SessionMetaPatch): Promise<void> {
    try {
      await ApiClient.shared.patch(`/sessions/${id}/meta`, patch);
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
        if (this.unread > 0) {
          Text(`${this.unread} unread`)
            .fontSize(Theme.fontTiny)
            .fontColor(Theme.onAccent)
            .backgroundColor(Theme.accent)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(Theme.radiusPill)
            .shadow({ radius: 10, color: Theme.accent, offsetX: 0, offsetY: 0 })
            .maxLines(1)
            .onClick(() => this.openFirstUnread())
        }
        Blank().layoutWeight(1)
        Button(this.archived ? 'Archived' : 'Active')
          .fontSize(Theme.fontTiny)
          .height(30)
          .backgroundColor(Theme.raised)
          .fontColor(this.archived ? Theme.muted : Theme.accent)
          .border({ width: 1, color: this.archived ? Theme.border : Theme.accent })
          .borderRadius(Theme.radiusPill)
          .onClick(() => {
            this.archived = !this.archived;
            this.applyFilter();
          })
      }
      .width(Theme.gutter)
      .padding({ top: 12, bottom: 10 })

      if (this.composing) {
        this.Composer()
      }

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
          this.FilterChip('全部', '')
          this.FilterChip('未读', 'unread')
          this.FilterChip('运行中', 'live')
          this.FilterChip('待确认', 'attention')
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

      if (this.groups.length === 0) {
        if (this.loading) {
          this.Skeleton()
        } else {
          Column() {
            Text(this.query.trim().length > 0
              ? `No sessions match “${this.query.trim()}”`
              : (this.archived ? 'No archived sessions' : 'No active sessions'))
              .fontSize(Theme.fontSmall)
              .fontColor(Theme.faint)
              .margin({ top: 60 })
          }
          .layoutWeight(1)
        }
      } else {
        Column() {
          Column() {
            List({ space: 10 }) {
              ForEach(this.groups, (group: ProjectGroup) => {
                // The header is a plain ListItem rather than a ListItemGroup
                // header: a ListItemGroup header did not receive taps here, and
                // its key carries the collapsed flag so ArkUI re-runs the branch
                // (a ForEach branch is only re-evaluated when its key changes).
                ListItem() {
                  this.GroupHeader(group, this.isCollapsed(group.name))
                }
                if (!this.isCollapsed(group.name)) {
                  ForEach(group.items, (item: SessionView, index: number) => {
                    ListItem() {
                      this.SessionRow(item, group.name, index)
                    }
                    .swipeAction({
                      end: {
                        builder: () => {
                          this.SwipeActions(item)
                        }
                      }
                    })
                  }, (item: SessionView) =>
                  // `status` and `connectorStatus` belong in the key: a status
                  // change does not necessarily bump `updatedSeq`, and a ForEach
                  // branch is only re-evaluated when its key changes — which is
                  // why rows sat on a stale status.
                  `${item.id}-${item.updatedSeq}-${item.status}-${item.connectorStatus}-${item.pinned}-${item.archived}-${item.unread}`)
                }
              }, (group: ProjectGroup) => `${group.name}-${this.isCollapsed(group.name) ? 1 : 0}`)

              // Bottom clearance as a real list item rather than List padding:
              // a bottom inset makes ArkUI stop painting the list ~320px early,
              // which is exactly what hid rows behind the floating bar.
              ListItem() {
                Row().height(Theme.barClearance)
              }
            }
            .width(Theme.gutter)
            .layoutWeight(1)
          }
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    // Transparent so the ambient light layer behind the tab shows through.
    .backgroundColor(Color.Transparent)
  }

  /**
   * Loading placeholder (加载动画). One highlight sweeping the whole stack, not a
   * shimmer per card: the sweep is a single animated element, and the inventory
   * is unbounded, so a per-card loop would repaint every frame.
   */
  @Builder
  Skeleton() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 10 }) {
        ForEach([0, 1, 2, 3, 4], (n: number) => {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Circle({ width: 7, height: 7 }).fill(Theme.border)
              Row()
                .height(14)
                .borderRadius(4)
                .backgroundColor(Theme.border)
                .layoutWeight(1)
            }
            .width('100%')

            Row()
              .height(11)
              .width('46%')
              .borderRadius(4)
              .backgroundColor(Theme.border)
          }
          .width('100%')
          .padding({
            left: Theme.spaceLg,
            right: Theme.spaceLg,
            top: Theme.spaceMd,
            bottom: Theme.spaceMd
          })
          .backgroundColor(Theme.surface)
          .borderRadius(Theme.radiusCard)
          .border({ width: 1, color: Theme.haloSoft })
          .alignItems(HorizontalAlign.Start)
        }, (n: number) => `skeleton-${n}`)
      }
      .width(Theme.gutter)

      Row()
        .width(Theme.gutter)
        .height(140)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [[Theme.haloFade, 0.0], [Theme.haloSoft, 0.5], [Theme.haloFade, 1.0]]
        })
        .translate({ y: this.sweep })
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ top: 8 })
    .clip(true)
  }

  /**
   * New-session composer. Inline rather than a sheet or dialog: the target
   * project has to stay visible, and it keeps the whole flow on one screen.
   */
  @Builder
  Composer() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(`在 ${this.newGroupName} 新建会话`)
          .fontSize(Theme.fontTiny)
          .fontColor(Theme.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('取消')
          .fontSize(Theme.fontTiny)
          .fontColor(Theme.muted)
          .onClick(() => {
            this.composing = false;
          })
      }
      .width('100%')

      TextArea({ placeholder: '第一条消息…', text: this.newDraft })
        .height(70)
        .fontSize(Theme.fontSmall)
        .backgroundColor(Theme.bg)
        .fontColor(Theme.text)
        .caretColor(Theme.accent)
        .placeholderColor(Theme.faint)
        .borderRadius(10)
        .onChange((v: string) => {
          this.newDraft = v;
        })

      Row({ space: 8 }) {
        Text(`${this.newRuntime} · ${this.newConnectorId}`)
          .fontSize(Theme.fontTiny)
          .fontColor(Theme.faint)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Button(this.creating ? '创建中…' : '创建并发送')
          .height(34)
          .fontSize(Theme.fontTiny)
          .enabled(!this.creating && this.newDraft.trim().length > 0)
          .backgroundColor(Theme.accent)
          .fontColor(Theme.onAccent)
          .borderRadius(Theme.radiusPill)
          .opacity(!this.creating && this.newDraft.trim().length > 0 ? 1 : 0.4)
          .onClick(() => {
            void this.createAndStart();
          })
      }
      .width('100%')
    }
    .width(Theme.gutter)
    .padding(14)
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.radiusCard)
    .border({ width: 1, color: Theme.haloSoft })
    .shadow({ radius: 12, color: Theme.shadow, offsetX: 0, offsetY: 3 })
    .alignItems(HorizontalAlign.Start)
  }

  /** Status facet chip. Distinct from the device chips so the two read apart. */
  @Builder
  FilterChip(label: string, value: string) {
    Text(label)
      .fontSize(Theme.fontTiny)
      .fontColor(this.statusFilter === value ? Theme.accent : Theme.muted)
      .backgroundColor(this.statusFilter === value ? Theme.accentTint : Theme.raised)
      .border({ width: 1, color: this.statusFilter === value ? Theme.accent : Theme.border })
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(Theme.radiusPill)
      .maxLines(1)
      .onClick(() => {
        this.statusFilter = value;
        this.applyFilter();
      })
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
  GroupHeader(group: ProjectGroup, collapsed: boolean) {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontColor([Theme.muted])
        .rotate({ angle: collapsed ? 0 : 90 })
        .width(14)
      Text(group.name)
        .fontSize(Theme.fontTiny)
        .fontColor(Theme.muted)
        .fontFamily('monospace')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(`${group.items.length}`)
        .fontSize(Theme.fontTiny)
        .fontColor(Theme.faint)
      // Its own tap target, so starting a session does not also toggle the
      // group. Plain ASCII '+': the full-width '＋' is missing from the system
      // font and renders as nothing at all.
      Text('+')
        .fontSize(Theme.fontHeading)
        .fontColor(Theme.accent)
        .padding({ left: 10, right: 4 })
        .onClick(() => this.startCompose(group))
    }
    .width('100%')
    .padding({ top: Theme.spaceLg, bottom: Theme.spaceSm })
    .backgroundColor(Color.Transparent)
    .onClick(() => this.toggleGroup(group.name))
  }

  @Builder
  SessionRow(item: SessionView, project: string, index: number) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        // Colour per state, and a pulse while that state is still changing.
        StatusDot({
          color: Fmt.statusColor(item.status),
          pulse: Fmt.statusLive(item.status),
          diameter: 7
        })
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
          Circle({ width: 7, height: 7 })
            .fill(Theme.accent)
            .shadow({ radius: 6, color: Theme.accent, offsetX: 0, offsetY: 0 })
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
        // Runtime stays plain text: it is a label, not a state, and chipping it
        // too left three grey pills on a card whose status was idle.
        Text(item.runtime)
          .fontSize(Theme.fontTiny)
          .fontColor(Theme.faint)
        StatusChip({
          label: item.connectorStatus === 'online' ? 'online' : 'offline',
          color: Fmt.linkColor(item.connectorStatus === 'online')
        })
        StatusChip({
          label: Fmt.statusLabel(item.status),
          color: Fmt.statusColor(item.status)
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({
      left: Theme.spaceLg,
      right: Theme.spaceLg,
      top: Theme.spaceMd,
      bottom: Theme.spaceMd
    })
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.radiusCard)
    // 光晕边框: an accent-tinted hairline reads as light catching the edge,
    // which is why it no longer looks like the grey table outline that an
    // opaque border produced on a flat background.
    .border({ width: 1, color: Theme.haloSoft })
    .shadow({ radius: 12, color: Theme.shadow, offsetX: 0, offsetY: 3 })
    .alignItems(HorizontalAlign.Start)
    // 弹性微交互: dip on touch-down, spring back on release. Press is fast and
    // release is slow, which is what reads as "physical".
    .scale({
      x: this.pressedId === item.id ? 0.97 : 1.0,
      y: this.pressedId === item.id ? 0.97 : 1.0
    })
    .animation({
      duration: this.pressedId === item.id ? 180 : 420,
      curve: Curve.FastOutSlowIn
    })
    // 模糊渐入: blur + rise, staggered. The delay is capped — at 60ms per row a
    // 300-session list would take 18 seconds to finish arriving.
    .opacity(this.revealed ? 1.0 : 0.0)
    .blur(this.revealed ? 0 : 8)
    .translate({ x: 0, y: this.revealed ? 0 : 24 })
    .animation({
      duration: 480,
      curve: Curve.EaseOut,
      delay: Math.min(index, 9) * 45
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedId = item.id;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedId = '';
      }
    })
    .onClick(() => {
      const param = new SessionDetailParam();
      param.id = item.id;
      this.rootStack.pushPath(new NavPathInfo('SessionDetail', param));
    })
  }

  /**
   * Swipe actions. `swipeAction.end` takes a single builder, so both actions
   * live in one row rather than as separate swipe stops.
   */
  @Builder
  SwipeActions(item: SessionView) {
    Row() {
      Button(item.archived ? 'Unarchive' : 'Archive')
        .fontSize(Theme.fontSmall)
        .height(48)
        .backgroundColor(Theme.raised)
        .fontColor(Theme.text)
        .borderRadius(0)
        .onClick(() => {
          const patch = new SessionMetaPatch();
          patch.archived = !item.archived;
          void this.patchMeta(item.id, patch);
        })
      Button(item.pinned ? 'Unpin' : 'Pin')
        .fontSize(Theme.fontSmall)
        .height(48)
        .backgroundColor(Theme.surface)
        .fontColor(Theme.text)
        .borderRadius(0)
        .onClick(() => {
          const patch = new SessionMetaPatch();
          patch.pinned = !item.pinned;
          void this.patchMeta(item.id, patch);
        })
    }
  }
}
