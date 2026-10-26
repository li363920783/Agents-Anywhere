import util from '@ohos.util';
import { promptAction } from '@kit.ArkUI';
import { ApiClient, UploadPart } from '../core/net/ApiClient';
import { ApiError } from '../core/net/ApiError';
import { RealtimeStream, RealtimeCallbacks } from '../core/net/RealtimeStream';
import { DashboardWatcher } from '../core/net/DashboardWatcher';
import { Notifier } from '../core/notify/Notifier';
import { Json } from '../core/util/Json';
import { Fmt } from '../core/util/Fmt';
import { Snapshot, TimelineItem, SessionView, Notice, NoticeAction, NoticeQuestion, NoticeQuestionOption, ToolContent, FileChangeContent, MarkerContent } from '../core/model/Session';
import { EmptyBody, AttachmentRef, FileReadRequest, MessageSendRequest, NoticeRespondRequest, SelectionPatchRequest, SessionMetaPatch } from '../core/model/Bodies';
import { ModelCatalog, ModelItem, PermissionCatalog, PermissionItem, TextFile } from '../core/model/Catalog';
import { WorkspaceParam } from '../core/model/Workspace';
import { picker, fileIo } from '@kit.CoreFileKit';
import cameraPicker from '@ohos.multimedia.cameraPicker';
import { camera } from '@kit.CameraKit';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import { MarkdownView } from '../ui/MarkdownView';
import { Theme } from '../core/ui/Theme';
import { Demo } from '../core/Demo';
import { StatusChip, StatusDot } from '../core/ui/Status';

/** Body of an optimistic user bubble, shaped like the server's message payload. */
class LocalMessageContent {
  text: string = '';
}

@Component
export struct SessionDetail {
  @Consume('rootStack') rootStack: NavPathStack;
  private sessionId: string = '';
  @State session: SessionView | null = null;
  /**
   * Status pushed by `runtime.state.updated`. `session.status` only changes when
   * the session meta is re-fetched, so without this the running indicator sat
   * still until you left the page and came back. Empty means "no live value".
   */
  @State liveStatus: string = '';
  @State items: Array<TimelineItem> = [];
  @State notices: Array<Notice> = [];
  /** Picked questionnaire options, keyed `<noticeId>|<questionId>|<optionId>`. */
  @State picks: Array<string> = [];
  @State composer: string = '';
  @State takeover: boolean = false;
  @State takeoverBusy: boolean = false;
  @State atBottom: boolean = true;
  /** Inline rename of the session title. */
  @State renaming: boolean = false;
  @State nameDraft: string = '';
  /** Id of the optimistic bubble shown while a send is in flight. */
  @State pendingId: string = '';
  @State connected: boolean = false;
  @State busy: boolean = false;
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State models: Array<ModelItem> = [];
  @State permissions: Array<PermissionItem> = [];
  @State modelIndex: number = -1;
  @State permissionIndex: number = -1;
  @State previewOpen: boolean = false;
  @State previewPath: string = '';
  @State previewName: string = '';
  @State previewContent: string = '';
  @State previewBinary: boolean = false;
  @State previewLoading: boolean = false;
  @State previewError: string = '';
  @State pendingParts: Array<UploadPart> = [];
  @State pendingCount: number = 0;
  /** Tool-call ids the user opened. Collapsed by default: most shell/read calls
   *  are noise until you actually want to read them. */
  @State expandedTools: Array<string> = [];
  private stream: RealtimeStream | null = null;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // Suppress notifications for the session the user is actually reading, and
    // drop the tray alert that led them here.
    DashboardWatcher.shared.activeSessionId = this.sessionId;
    void Notifier.clear(this.sessionId);
    void this.load();
  }

  aboutToDisappear(): void {
    this.stream?.stop();
    this.stream = null;
    // Keep suppressing for a moment: `unread` is derived from seq vs last-read,
    // so a message the user just sent here re-reads as unread, and that snapshot
    // lands after this page is gone. Without the grace period the app would
    // notify the user about their own send.
    setTimeout(() => {
      if (DashboardWatcher.shared.activeSessionId === this.sessionId) {
        DashboardWatcher.shared.activeSessionId = '';
      }
    }, 10000);
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg, duration: 2000 });
  }

  /** Opens the workspace browser/runner scoped to this session's cwd. */
  private openWorkspace(): void {
    const param = new WorkspaceParam();
    param.connectorId = this.session?.connectorId ?? '';
    param.root = this.session?.cwd ?? '.';
    param.title = this.session?.title ?? 'Workspace';
    this.rootStack.pushPath(new NavPathInfo('Workspace', param));
  }

  /** Current branch, falling back to the worktree name when the runtime reports none. */
  private branchLabel(): string {    const branch = this.session?.gitBranch;
    if (branch !== undefined && branch !== null && branch.length > 0) {
      return branch;
    }
    const cwd = this.session?.cwd ?? '';
    const parts = cwd.split(/[\\/]/).filter((p: string) => p.length > 0);
    return parts.length > 0 ? parts[parts.length - 1] : '';
  }

  async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const snap = Demo.on()
        ? Snapshot.fromJson(Demo.snapshot())
        : Snapshot.fromJson(await ApiClient.shared.get(`/sessions/${this.sessionId}/snapshot?limit=200`));
      this.session = snap.session;
      // The snapshot carries the authoritative status, so drop the live overlay
      // until the stream tells us something newer.
      this.liveStatus = '';
      this.items = snap.timeline;
      this.notices = snap.notices;
      this.takeover = snap.session.takeover;
    } catch (e) {
      const err = e as Error;
      const msg = err instanceof ApiError ? err.message : 'snapshot failed';
      this.errorMsg = msg;
    } finally {
      this.loading = false;
    }
    if (!Demo.on()) {
      this.connectStream();
    }
    void this.markRead();
    void this.loadCatalogs();
    this.scrollToBottom(120);
  }

  /**
   * Opening a session is what "reading" it means. Both the row's unread dot and
   * the header badge are derived server-side from `last_read_seq`, so they only
   * clear once this lands — without it the badge never came down.
   */
  private async markRead(): Promise<void> {
    try {
      await ApiClient.shared.post('/sessions/read', [this.sessionId]);
    } catch (e) {
      // Best effort. A lost receipt is corrected by the next open, and it must
      // not stop the session from being usable.
    }
  }

  /** Renames the session; the dashboard snapshot pushes the new title back. */
  private async saveName(): Promise<void> {
    const name = this.nameDraft.trim();
    if (name.length === 0) {
      this.renaming = false;
      return;
    }
    try {
      const patch = new SessionMetaPatch();
      patch.title = name;
      await ApiClient.shared.patch(`/sessions/${this.sessionId}/meta`, patch);
      this.renaming = false;
    } catch (e) {
      const err = e as Error;
      promptAction.showToast({
        message: err instanceof ApiError ? err.message : 'rename failed',
        duration: 1500
      });
    }
  }

  private scrollToBottom(delay: number): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
      this.atBottom = true;
    }, delay);
  }

  /** Index whose selectionId matches, or -1. `applySelection` stores selectionIds. */
  private indexOfSelection(selectionIds: Array<string>, wanted: string): number {
    if (wanted.length === 0) {
      return -1;
    }
    for (let i = 0; i < selectionIds.length; i++) {
      if (selectionIds[i] === wanted) {
        return i;
      }
    }
    return -1;
  }

  private defaultIndex(flags: Array<boolean>): number {
    for (let i = 0; i < flags.length; i++) {
      if (flags[i]) {
        return i;
      }
    }
    return -1;
  }

  private async loadCatalogs(): Promise<void> {
    // The session remembers the last selection the server applied; the catalog
    // default is only a fallback. Without this the pickers reset on every visit.
    let selectedModel = '';
    let selectedPermission = '';
    try {
      const stateRes = await ApiClient.shared.get(`/sessions/${this.sessionId}/runtime/state`);
      const selections = Json.obj(Json.obj(stateRes, 'state'), 'selections');
      selectedModel = Json.str(selections, 'model') ?? '';
      selectedPermission = Json.str(selections, 'permission') ?? '';
    } catch (e) {
      // best-effort: fall through to catalog defaults
    }

    try {
      const modelRes = await ApiClient.shared.get(`/sessions/${this.sessionId}/runtime/catalogs/model`);
      const modelCatalog = ModelCatalog.fromJson(Json.obj(modelRes, 'catalog'));
      this.models = modelCatalog.models;
      const selectionIds: Array<string> = this.models.map((m: ModelItem) => m.selectionId);
      const defaults: Array<boolean> = this.models.map((m: ModelItem) => m.isDefault);
      let mi = this.indexOfSelection(selectionIds, selectedModel);
      if (mi < 0) {
        mi = this.defaultIndex(defaults);
      }
      this.modelIndex = mi >= 0 ? mi : (this.models.length > 0 ? 0 : -1);
    } catch (e) {
      // best-effort: keep default model
    }
    try {
      const permissionRes = await ApiClient.shared.get(`/sessions/${this.sessionId}/runtime/catalogs/permission`);
      const permissionCatalog = PermissionCatalog.fromJson(Json.obj(permissionRes, 'catalog'));
      this.permissions = permissionCatalog.permissions;
      const selectionIds: Array<string> = this.permissions.map((p: PermissionItem) => p.selectionId);
      const defaults: Array<boolean> = this.permissions.map((p: PermissionItem) => p.isDefault);
      let pi = this.indexOfSelection(selectionIds, selectedPermission);
      if (pi < 0) {
        pi = this.defaultIndex(defaults);
      }
      this.permissionIndex = pi >= 0 ? pi : (this.permissions.length > 0 ? 0 : -1);
    } catch (e) {
      // best-effort: keep default permission
    }
  }

  private modelLabel(): string {
    if (this.modelIndex >= 0 && this.modelIndex < this.models.length) {
      const m = this.models[this.modelIndex];
      return m.displayName.length > 0 ? m.displayName : m.id;
    }
    return 'Model';
  }

  private permissionLabel(): string {
    if (this.permissionIndex >= 0 && this.permissionIndex < this.permissions.length) {
      const p = this.permissions[this.permissionIndex];
      return p.displayName.length > 0 ? p.displayName : p.id;
    }
    return 'Permission';
  }

  /** Model/permission changes go to their own endpoint; the message body rejects extra fields. */
  private async applySelection(key: string, index: number): Promise<void> {
    let selectionId = '';
    if (key === 'model' && index >= 0 && index < this.models.length) {
      selectionId = this.models[index].selectionId;
    } else if (key === 'permission' && index >= 0 && index < this.permissions.length) {
      selectionId = this.permissions[index].selectionId;
    }
    if (selectionId.length === 0) {
      return;
    }
    try {
      const body = new SelectionPatchRequest();
      body.selections[key] = selectionId;
      await ApiClient.shared.patch(`/sessions/${this.sessionId}/runtime/selections`, body);
    } catch (e) {
      const err = e as Error;
      const msg = err instanceof ApiError ? err.message : 'selection failed';
      this.toast(msg);
    }
  }

  private modelOptions(): Array<SelectOption> {
    const options: Array<SelectOption> = [];
    for (let i = 0; i < this.models.length; i++) {
      const m = this.models[i];
      const opt: SelectOption = { value: m.displayName.length > 0 ? m.displayName : m.id };
      options.push(opt);
    }
    return options;
  }

  private permissionOptions(): Array<SelectOption> {
    const options: Array<SelectOption> = [];
    for (let i = 0; i < this.permissions.length; i++) {
      const p = this.permissions[i];
      const opt: SelectOption = { value: p.displayName.length > 0 ? p.displayName : p.id };
      options.push(opt);
    }
    return options;
  }

  private async openFilePreview(path: string): Promise<void> {
    this.previewPath = path;
    const slash = path.lastIndexOf('/');
    this.previewName = slash >= 0 ? path.substring(slash + 1) : path;
    this.previewContent = '';
    this.previewError = '';
    this.previewBinary = false;
    this.previewLoading = true;
    this.previewOpen = true;
    try {
      const body = new FileReadRequest();
      body.path = path;
      const root = this.session?.cwd ?? '.';
      const connectorId = this.session?.connectorId ?? '';
      const res = await ApiClient.shared.post(
        `/connectors/${connectorId}/fs/readText?root=${encodeURIComponent(root)}`,
        body,
      );
      const file = TextFile.fromJson(res);
      if (file.name.length > 0) {
        this.previewName = file.name;
      }
      this.previewContent = file.content;
      this.previewBinary = file.binary;
    } catch (e) {
      const err = e as Error;
      this.previewError = err instanceof ApiError ? err.message : 'failed to open file';
    } finally {
      this.previewLoading = false;
    }
  }

  private async savePreview(): Promise<void> {
    if (this.previewContent.length === 0) {
      return;
    }
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [this.previewName.length > 0 ? this.previewName : 'file.txt'];
      const documentPicker = new picker.DocumentViewPicker();
      const uris = await documentPicker.save(options);
      if (uris.length > 0) {
        const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        fileIo.writeSync(file.fd, this.previewContent);
        fileIo.closeSync(file);
        this.toast('Saved');
      }
    } catch (e) {
      this.toast('Save failed');
    }
  }

  /** Reads a picked uri into memory and queues it for the next send. */
  private addAttachment(uri: string, mediaType: string, name: string): void {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    const stat = fileIo.statSync(file.fd);
    const buffer = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buffer);
    fileIo.closeSync(file);
    this.pendingParts.push(new UploadPart(name, mediaType, buffer));
    this.pendingCount = this.pendingParts.length;
  }

  private async capturePhoto(): Promise<void> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
        saveUri: '',
        videoDuration: 0
      };
      const result = await cameraPicker.pick(
        getContext(this),
        [cameraPicker.PickerMediaType.PHOTO],
        profile
      );
      if (result.resultCode !== 0 || result.resultUri.length === 0) {
        return;
      }
      this.addAttachment(result.resultUri, 'image/jpeg', `photo-${Date.now()}.jpg`);
    } catch (e) {
      this.toast('Camera unavailable');
    }
  }

  private async pickPhotos(): Promise<void> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 5;
      const result = await new photoAccessHelper.PhotoViewPicker().select(options);
      for (let i = 0; i < result.photoUris.length; i++) {
        this.addAttachment(result.photoUris[i], 'image/jpeg', `photo-${Date.now()}-${i}.jpg`);
      }
    } catch (e) {
      this.toast('Pick failed');
    }
  }

  private async pickAttachments(): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 5;
      const documentPicker = new picker.DocumentViewPicker();
      const uris = await documentPicker.select(options);
      for (let i = 0; i < uris.length; i++) {
        const uri = uris[i];
        const slash = uri.lastIndexOf('/');
        const name = slash >= 0 ? uri.substring(slash + 1) : 'attachment';
        this.addAttachment(uri, 'application/octet-stream', name);
      }
    } catch (e) {
      this.toast('Pick failed');
    }
  }

  private connectStream(): void {
    this.stream?.stop();
    const cb = new RealtimeCallbacks();
    cb.onOpen = () => {
      this.connected = true;
    };
    cb.onClose = () => {
      this.connected = false;
    };
    cb.onError = (msg: string) => {
      this.connected = false;
    };
    cb.onText = (text: string) => {
      this.applyFrame(text);
    };
    const stream = new RealtimeStream(this.sessionId, cb);
    this.stream = stream;
    stream.start(util.generateRandomUUID()).catch((e: Error) => {
      this.connected = false;
    });
  }

  private applyFrame(text: string): void {
    const frame = Json.parse(text);
    if (frame === null) {
      return;
    }
    if (Json.str(frame, 'type') === 'keepalive') {
      return;
    }
    const type = Json.strOr(frame, 'type', '');
    const rawPayload = Json.obj(frame, 'payload');
    const payload: Object = rawPayload === null ? new EmptyBody() : rawPayload;
    switch (type) {
      case 'timeline.item_created':
      case 'timeline.item_updated': {
        const item = Json.obj(payload, 'item');
        if (item !== null) {
          const parsed = TimelineItem.fromJson(item);
          // The server echoed our own message: swap the optimistic bubble out.
          if (parsed.role === 'user' && this.pendingId.length > 0) {
            this.dropPending();
          }
          this.mergeItem(parsed);
        }
        break;
      }
      case 'timeline.snapshot': {
        const raw = Json.arr(payload, 'items') ?? [];
        this.items = raw.map((o: Object) => TimelineItem.fromJson(o));
        break;
      }
      case 'session.meta.updated': {
        const s = Json.obj(payload, 'session');
        if (s !== null) {
          const view = SessionView.fromJson(s);
          this.session = view;
          if (!this.takeoverBusy) {
            this.takeover = view.takeover;
          }
        }
        break;
      }
      case 'runtime.notice.snapshot': {
        const raw = Json.arr(payload, 'notices') ?? [];
        this.notices = raw.map((o: Object) => Notice.fromJson(o));
        break;
      }
      case 'runtime.notice.updated': {
        const n = Json.obj(payload, 'notice');
        if (n === null) break;
        const notice = Notice.fromJson(n);
        const idx = this.notices.findIndex((x: Notice) => x.noticeId === notice.noticeId);
        if (idx >= 0) {
          if (notice.status === 'resolved' || notice.status === 'closed') {
            this.notices.splice(idx, 1);
          } else {
            this.notices[idx] = notice;
          }
        } else if (!(notice.status === 'resolved' || notice.status === 'closed')) {
          this.notices.push(notice);
        }
        break;
      }
      case 'runtime.state.updated': {
        const state = Json.obj(payload, 'state');
        const status = state === null ? null : Json.str(state, 'status');
        if (status !== null && status.length > 0) {
          this.liveStatus = status;
        }
        break;
      }
      case 'session.refetch_required':
        void this.load();
        break;
      default:
        break;
    }
  }

  /** Live status wins over the one baked into the last snapshot. */
  private currentStatus(): string {
    if (this.liveStatus.length > 0) {
      return this.liveStatus;
    }
    return this.session?.status ?? '';
  }

  private mergeItem(item: TimelineItem): void {
    const idx = this.items.findIndex((x: TimelineItem) => x.id === item.id);
    if (idx >= 0) {
      this.items[idx] = item;
    } else {
      const pos = this.items.findIndex((x: TimelineItem) => x.orderSeq > item.orderSeq);
      if (pos < 0) {
        this.items.push(item);
        if (this.atBottom) {
          this.scrollToBottom(30);
        }
      } else {
        this.items.splice(pos, 0, item);
      }
    }
  }

  /** Idle sessions only have one meaning for a message. */
  private async send(): Promise<void> {
    await this.sendVia('messages');
  }

  /**
   * Every send path — queue, steer, interrupt — is rejected by the server
   * until the session is taken over, so the toggle is a prerequisite rather
   * than a preference. Turning it on here beats failing with a 409 the user
   * cannot act on.
   */
  private async ensureTakeover(): Promise<boolean> {
    if (this.takeover) {
      return true;
    }
    await this.setTakeover(true);
    return this.takeover;
  }

  private async sendVia(endpoint: string): Promise<void> {
    const content = this.composer.trim();
    if (content.length === 0) {
      return;
    }
    if (!await this.ensureTakeover()) {
      return;
    }
    this.busy = true;
    // Show the message immediately: the real item only arrives over the stream a
    // few seconds later, and without a pending bubble the send looks like a no-op.
    const clientMessageId = util.generateRandomUUID();
    const pending = new TimelineItem();
    pending.id = `local_${clientMessageId}`;
    pending.sessionId = this.sessionId;
    pending.type = 'message';
    pending.role = 'user';
    pending.status = 'pending';
    pending.orderSeq = Number.MAX_SAFE_INTEGER;
    const localContent = new LocalMessageContent();
    localContent.text = content;
    pending.content = localContent;
    this.items.push(pending);
    this.pendingId = pending.id;
    this.composer = '';
    this.scrollToBottom(30);
    try {
      const sendBody = new MessageSendRequest();
      sendBody.content = content;
      sendBody.attachments = [];
      if (this.pendingParts.length > 0) {
        const uploadRes = await ApiClient.shared.postMultipart(
          `/sessions/${this.sessionId}/attachments`,
          this.pendingParts,
        );
        const refs = Json.arr(uploadRes, 'attachments') ?? [];
        const attachments: Array<Object> = [];
        for (let i = 0; i < refs.length; i++) {
          const ref = new AttachmentRef();
          ref.fileId = Json.strOr(refs[i], 'fileId', '');
          attachments.push(ref);
        }
        sendBody.attachments = attachments;
      }
      sendBody.clientMessageId = clientMessageId;
      await ApiClient.shared.post(`/sessions/${this.sessionId}/runtime/${endpoint}`, sendBody);
      this.pendingParts = [];
      this.pendingCount = 0;
    } catch (e) {
      this.dropPending();
      this.composer = content;
      const err = e as Error;
      const msg = err instanceof ApiError ? err.message : 'send failed';
      this.toast(msg);
    } finally {
      this.busy = false;
    }
  }

  /** Removes the optimistic bubble once the server's copy arrives (or the send fails). */
  private dropPending(): void {
    if (this.pendingId.length === 0) {
      return;
    }
    const id = this.pendingId;
    this.items = this.items.filter((x: TimelineItem) => x.id !== id);
    this.pendingId = '';
  }

  private async setTakeover(next: boolean): Promise<void> {
    if (this.takeoverBusy || next === this.takeover) {
      return;
    }
    this.takeoverBusy = true;
    this.takeover = next;
    try {
      if (next) {
        await ApiClient.shared.post(`/sessions/${this.sessionId}/takeover`, new EmptyBody());
      } else {
        await ApiClient.shared.del(`/sessions/${this.sessionId}/takeover`);
      }
    } catch (e) {
      const err = e as Error;
      this.takeover = !next;
      const msg = err instanceof ApiError ? err.message : 'takeover failed';
      this.toast(msg);
    } finally {
      this.takeoverBusy = false;
    }
  }

  private async interrupt(): Promise<void> {
    if (!await this.ensureTakeover()) {
      return;
    }
    try {
      await ApiClient.shared.post(`/sessions/${this.sessionId}/runtime/interrupt`, new EmptyBody());
      this.toast('Interrupt sent');
    } catch (e) {
      const err = e as Error;
      this.toast(err instanceof ApiError ? err.message : 'interrupt failed');
    }
  }

  /**
   * Stops the running turn, then sends what is in the composer as the next
   * turn. The interrupt is best-effort: if it fails, the send still runs and
   * reports whatever actually blocks it — a queued message beats a lost one.
   */
  private async interruptAndSend(): Promise<void> {
    if (this.composer.trim().length === 0) {
      return;
    }
    if (!await this.ensureTakeover()) {
      return;
    }
    try {
      await ApiClient.shared.post(`/sessions/${this.sessionId}/runtime/interrupt`, new EmptyBody());
    } catch (e) {
      // Intentional: sendVia() below surfaces the real reason.
    }
    await this.sendVia('messages');
  }

  private async respond(noticeId: string, actionId: string, input: Object | null = null): Promise<void> {
    try {
      const respondBody = new NoticeRespondRequest();
      respondBody.actionId = actionId;
      respondBody.input = input;
      await ApiClient.shared.post(`/sessions/${this.sessionId}/runtime/notices/${noticeId}/respond`, respondBody);
      this.notices = this.notices.filter((n: Notice) => n.noticeId !== noticeId);
      this.picks = this.picks.filter((k: string) => !k.startsWith(`${noticeId}|`));
    } catch (e) {
      const err = e as Error;
      this.toast(err instanceof ApiError ? err.message : 'respond failed');
    }
  }

  private pickKey(noticeId: string, questionId: string, optionId: string): string {
    return `${noticeId}|${questionId}|${optionId}`;
  }

  private isPicked(noticeId: string, questionId: string, optionId: string): boolean {
    return this.picks.indexOf(this.pickKey(noticeId, questionId, optionId)) >= 0;
  }

  private togglePick(noticeId: string, question: NoticeQuestion, optionId: string): void {
    const key = this.pickKey(noticeId, question.questionId, optionId);
    if (question.multiple) {
      const at = this.picks.indexOf(key);
      this.picks = at >= 0
        ? this.picks.filter((k: string) => k !== key)
        : this.picks.concat([key]);
      return;
    }
    // Single select: drop the other options of this question, keep the rest.
    const prefix = `${noticeId}|${question.questionId}|`;
    this.picks = this.picks.filter((k: string) => !k.startsWith(prefix)).concat([key]);
  }

  private pickedOf(noticeId: string, questionId: string): Array<string> {
    const prefix = `${noticeId}|${questionId}|`;
    const out: Array<string> = [];
    for (let i = 0; i < this.picks.length; i++) {
      const key = this.picks[i];
      if (key.startsWith(prefix)) {
        out.push(key.substring(prefix.length));
      }
    }
    return out;
  }

  private answersComplete(noticeId: string, questions: Array<NoticeQuestion>): boolean {
    for (let i = 0; i < questions.length; i++) {
      if (this.pickedOf(noticeId, questions[i].questionId).length === 0) {
        return false;
      }
    }
    return questions.length > 0;
  }

  /**
   * Builds the connector's answer shape: `{"answers": {"q_0": {"optionIds":
   * ["o_1"]}}}`. Assembled as JSON text because ArkTS will not accept a nested
   * object literal here; the ids are ours, so there is nothing to escape.
   */
  private buildAnswers(noticeId: string, questions: Array<NoticeQuestion>): Object | null {
    const parts: Array<string> = [];
    for (let i = 0; i < questions.length; i++) {
      const q = questions[i];
      const ids = JSON.stringify(this.pickedOf(noticeId, q.questionId));
      parts.push(`"${q.questionId}":{"optionIds":${ids}}`);
    }
    if (parts.length === 0) {
      return null;
    }
    return JSON.parse(`{"answers":{${parts.join(',')}}}`);
  }

  private submitAnswers(n: Notice): void {
    const questions = n.questions();
    if (!this.answersComplete(n.noticeId, questions)) {
      return;
    }
    void this.respond(n.noticeId, 'submit', this.buildAnswers(n.noticeId, questions));
  }

  build() {
    Stack() {
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
        Circle({ width: 8, height: 8 })
          .fill(this.session?.connectorStatus === 'online' ? Theme.accent : Theme.faint)
          .margin({ top: 6 })
        Column({ space: 3 }) {
          if (this.renaming) {
            Row({ space: 8 }) {
              TextInput({ text: this.nameDraft })
                .height(36)
                .layoutWeight(1)
                .fontSize(Theme.fontBody)
                .backgroundColor(Theme.raised)
                .fontColor(Theme.text)
                .caretColor(Theme.accent)
                .borderRadius(8)
                .onChange((v: string) => {
                  this.nameDraft = v;
                })
                .onSubmit(() => {
                  void this.saveName();
                })
              Button('保存')
                .height(36)
                .fontSize(Theme.fontTiny)
                .backgroundColor(Theme.accent)
                .fontColor(Theme.onAccent)
                .borderRadius(8)
                .onClick(() => {
                  void this.saveName();
                })
            }
            .width('100%')
          } else {
            Text(this.session?.title ?? this.session?.cwd ?? this.sessionId)
              .fontSize(Theme.fontHeading)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.branchLabel().length > 0) {
            Text(this.branchLabel())
              .fontSize(Theme.fontTiny)
              .fontFamily('monospace')
              .fontColor(Theme.muted)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .backgroundColor(Theme.surface)
              .border({ width: 1, color: Theme.border })
              .borderRadius(4)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width(Theme.gutter)
      .padding({ top: 10, bottom: 6 })

      Row({ space: 8 }) {
        StatusDot({
          color: Fmt.statusColor(this.currentStatus()),
          pulse: Fmt.statusLive(this.currentStatus()),
          diameter: 8
        })
        StatusChip({
          label: Fmt.statusLabel(this.currentStatus()),
          color: Fmt.statusColor(this.currentStatus())
        })
        Blank().layoutWeight(1)
        Text('重命名')
          .fontSize(Theme.fontTiny)
          .fontColor(Theme.muted)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .border({ width: 1, color: Theme.border })
          .borderRadius(Theme.radiusPill)
          .onClick(() => {
            this.nameDraft = this.session?.title ?? '';
            this.renaming = true;
          })
        Text('工作区')
          .fontSize(Theme.fontTiny)
          .fontColor(Theme.muted)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .border({ width: 1, color: Theme.border })
          .borderRadius(Theme.radiusPill)
          .onClick(() => this.openWorkspace())
        Button('Interrupt')
          .fontSize(Theme.fontTiny)
          .height(28)
          .backgroundColor(Theme.raised)
          .fontColor(Theme.danger)
          .borderRadius(Theme.radiusPill)
          .onClick(() => this.interrupt())
      }
      .width(Theme.gutter)
      .padding({ bottom: 8 })

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.danger)
          .width(Theme.gutter)
          .padding(8)
          .wordBreak(WordBreak.BREAK_ALL)
      }

      Stack({ alignContent: Alignment.BottomEnd }) {
        Scroll(this.scroller) {
          Column({ space: 10 }) {
            ForEach(this.items, (item: TimelineItem) => {
              // The wrapper exists for the transition: a @Builder call cannot
              // take modifiers, and every new item — optimistic or streamed —
              // should fade in rather than appear.
              Column() {
                this.TimelineRow(item)
              }
              .width('100%')
              .transition(TransitionEffect.OPACITY.animation({
                duration: 240,
                curve: Curve.EaseOut
              }))
            }, (item: TimelineItem) => `${item.id}-${item.revision}-${item.updatedSeq}`)
            if (this.loading && this.items.length === 0) {
              LoadingProgress()
                .width(24)
                .height(24)
            }
          }
          .width(Theme.gutter)
          .padding({ bottom: 12 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .onScroll(() => {
          this.atBottom = false;
        })
        .onScrollEdge((side: Edge) => {
          this.atBottom = side === Edge.Bottom;
        })

        if (!this.atBottom) {
          Stack() {
            Row()
              .width(11)
              .height(11)
              .border({ width: { bottom: 2, right: 2 }, color: '#FFFFFF' })
              .rotate({ angle: 45 })
              .margin({ bottom: 5 })
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(Theme.raised)
          .border({ width: 1, color: Theme.borderStrong })
          .shadow({ radius: 10, color: '#000000', offsetX: 0, offsetY: 3 })
          .margin({ right: 16, bottom: 12 })
          .onClick(() => this.scrollToBottom(0))
        }
      }
      .layoutWeight(1)
      .width('100%')

      Row({ space: 8 }) {
        Select(this.modelOptions())
          .selected(this.modelIndex)
          .value(this.modelLabel())
          .font({ size: Theme.fontTiny })
          .fontColor(Theme.text)
          .backgroundColor(Theme.surface)
          .selectedOptionBgColor(Theme.accent)
          .selectedOptionFontColor(Theme.onAccent)
          .optionBgColor(Theme.raised)
          .optionFontColor(Theme.text)
          .layoutWeight(1)
          .onSelect((index: number) => {
            this.modelIndex = index;
            void this.applySelection('model', index);
          })
        Select(this.permissionOptions())
          .selected(this.permissionIndex)
          .value(this.permissionLabel())
          .font({ size: Theme.fontTiny })
          .fontColor(Theme.text)
          .backgroundColor(Theme.surface)
          .selectedOptionBgColor(Theme.accent)
          .selectedOptionFontColor(Theme.onAccent)
          .optionBgColor(Theme.raised)
          .optionFontColor(Theme.text)
          .layoutWeight(1)
          .onSelect((index: number) => {
            this.permissionIndex = index;
            void this.applySelection('permission', index);
          })
      }
      .width(Theme.gutter)
      .padding({ top: 6 })

      // Without this the page looks identical whether the agent is working or
      // idle — the only cue was a word in the header.
      if (Fmt.statusLive(this.currentStatus())) {
        Row({ space: 7 }) {
          StatusDot({
            color: Fmt.statusColor(this.currentStatus()),
            pulse: true,
            diameter: 8
          })
          Text(`Agent 正在运行 · ${Fmt.statusLabel(this.currentStatus())}`)
            .fontSize(Theme.fontTiny)
            .fontColor(Theme.muted)
          Blank().layoutWeight(1)
        }
        .width(Theme.gutter)
        .padding({ top: 8 })
      }

      // Prompts sit above the composer, not at the top of the timeline. The
      // answer is needed *now*, and a long history buries the card off-screen:
      // the session sat in Waiting with no reachable way to reply.
      if (this.notices.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.notices, (n: Notice) => {
            this.NoticeCard(n)
          }, (n: Notice) => n.noticeId)
        }
        .width(Theme.gutter)
        .padding({ top: 8 })
      }

      Row({ space: 8 }) {
        Button(this.pendingCount > 0 ? `+${this.pendingCount}` : '+')
          .height(42)
          .width(42)
          .fontSize(Theme.fontHeading)
          .backgroundColor(Theme.raised)
          .fontColor(Theme.text)
          .borderRadius(Theme.radiusPill)
          .bindMenu([
            {
              value: '拍照',
              action: () => {
                void this.capturePhoto();
              }
            },
            {
              value: '从相册选择',
              action: () => {
                void this.pickPhotos();
              }
            },
            {
              value: '选择文件',
              action: () => {
                void this.pickAttachments();
              }
            }
          ])
        TextArea({ placeholder: this.takeover ? 'Send a command…' : 'Send a message…', text: this.composer })
          .height(42)
          .layoutWeight(1)
          .fontSize(Theme.fontBody)
          .backgroundColor(Theme.surface)
          .fontColor(Theme.text)
          .caretColor(Theme.accent)
          .placeholderColor(Theme.faint)
          .borderRadius(Theme.radiusPill)
          .onChange((v: string) => {
            this.composer = v;
          })
        if (Fmt.statusLive(this.currentStatus())) {
          // Two visible actions instead of a menu: while a turn runs, "wait for
          // the current turn" and "stop it and go now" are both one tap, and
          // neither is hidden behind a long-press nobody discovers.
          Button('打断并发送')
            .height(42)
            .fontSize(Theme.fontTiny)
            .fontColor(Theme.danger)
            .backgroundColor(Theme.raised)
            .borderRadius(Theme.radiusPill)
            .enabled(!this.busy && this.connected)
            .opacity(!this.busy && this.connected ? 1 : 0.4)
            .onClick(() => {
              void this.interruptAndSend();
            })
          Button('排队')
            .height(42)
            .fontSize(Theme.fontSmall)
            .fontWeight(FontWeight.Medium)
            .enabled(!this.busy && this.connected)
            .backgroundColor(Theme.accent)
            .fontColor(Theme.onAccent)
            .borderRadius(Theme.radiusPill)
            .opacity(!this.busy && this.connected ? 1 : 0.4)
            .onClick(() => {
              void this.sendVia('messages');
            })
        } else {
          Button('Send')
            .height(42)
            .fontSize(Theme.fontSmall)
            .fontWeight(FontWeight.Medium)
            .enabled(!this.busy && this.connected)
            .backgroundColor(Theme.accent)
            .fontColor(Theme.onAccent)
            .borderRadius(Theme.radiusPill)
            .opacity(!this.busy && this.connected ? 1 : 0.4)
            .onClick(() => this.send())
        }
      }
      .width(Theme.gutter)
      .padding({ bottom: 10, top: 8 })

      Row({ space: 8 }) {
        Column({ space: 1 }) {
          Text('Takeover')
            .fontSize(Theme.fontSmall)
            .fontColor(Theme.text)
          Text(this.takeover ? 'Messages you send steer the run' : 'Read-only while the agent drives')
            .fontSize(Theme.fontTiny)
            .fontColor(Theme.faint)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.takeover })
          .selectedColor(Theme.accent)
          .onChange((on: boolean) => {
            void this.setTakeover(on);
          })
      }
      .width(Theme.gutter)
      .padding({ bottom: 14 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)

    if (this.previewOpen) {
      this.FilePreviewOverlay()
    }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  FilePreviewOverlay() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.previewName)
          .fontSize(Theme.fontSmall)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .fontFamily('monospace')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_ALL)
        Button('Save')
          .fontSize(Theme.fontTiny)
          .height(30)
          .enabled(this.previewContent.length > 0)
          .backgroundColor(Theme.accent)
          .fontColor(Theme.onAccent)
          .borderRadius(Theme.radiusPill)
          .opacity(this.previewContent.length > 0 ? 1 : 0.4)
          .onClick(() => { void this.savePreview(); })
        Button('Close')
          .fontSize(Theme.fontTiny)
          .height(30)
          .backgroundColor(Theme.raised)
          .fontColor(Theme.text)
          .borderRadius(Theme.radiusPill)
          .onClick(() => { this.previewOpen = false; })
      }
      .width('100%')

      Scroll() {
        Text(this.previewLoading ? 'Loading…' : (this.previewError.length > 0 ? this.previewError : this.previewContent))
          .fontSize(Theme.fontTiny)
          .lineHeight(18)
          .fontFamily('monospace')
          .fontColor(Theme.text)
          .wordBreak(WordBreak.BREAK_ALL)
          .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
    }
    .width(Theme.gutter)
    .height('74%')
    .padding(14)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderStrong })
    .borderRadius(18)
  }

  /**
   * Runtime thinking blocks arrive as `type: 'system'` with `kind: 'reasoning'`
   * (or as a dedicated `reasoning` type); both render as collapsed reasoning,
   * not as a centered marker.
   */
  private isReasoning(item: TimelineItem): boolean {
    if (item.type === 'reasoning') {
      return true;
    }
    return item.type === 'system' && Json.strOr(item.content, 'kind', '') === 'reasoning';
  }

  private isToolExpanded(id: string): boolean {
    return this.expandedTools.indexOf(id) >= 0;
  }

  private toggleTool(id: string): void {
    const next: Array<string> = [];
    let removed = false;
    for (let i = 0; i < this.expandedTools.length; i++) {
      if (this.expandedTools[i] === id) {
        removed = true;
        continue;
      }
      next.push(this.expandedTools[i]);
    }
    if (!removed) {
      next.push(id);
    }
    this.expandedTools = next;
  }

  /** One-line gist for a collapsed tool call: the command, or the target path. */
  private toolSummary(item: TimelineItem): string {
    const input = Json.obj(item.content, 'input');
    const command = Json.str(input, 'command');
    if (command !== null && command.trim().length > 0) {
      return command.replace(/\s+/g, ' ').trim();
    }
    const path = Json.str(input, 'file_path') ?? Json.str(input, 'path');
    if (path !== null && path.length > 0) {
      return path;
    }
    // AskUserQuestion's payload is a JSON blob; the prompts are what a reader
    // wants, and the raw blob only helps when expanded.
    const questions = Json.arr(input, 'questions');
    if (questions !== null && questions.length > 0) {
      const prompts: Array<string> = [];
      for (let i = 0; i < questions.length; i++) {
        const prompt = Json.str(questions[i], 'question');
        if (prompt !== null && prompt.length > 0) {
          prompts.push(prompt);
        }
      }
      if (prompts.length > 0) {
        return prompts.join(' / ');
      }
    }
    return ToolContent.inputText(item.content).replace(/\s+/g, ' ').trim();
  }

  @Builder
  TimelineRow(item: TimelineItem) {
    if (this.isReasoning(item)) {
      Column() {
        Text(TimelineItem.displayText(item))
          .fontSize(Theme.fontTiny)
          .lineHeight(18)
          .fontColor(Theme.faint)
          .fontStyle(FontStyle.Italic)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_ALL)
      }
      .width('100%')
      .padding({ left: 10, top: 2, bottom: 2 })
      .border({ width: { left: 2 }, color: Theme.border })
      .alignItems(HorizontalAlign.Start)
    } else if (item.type === 'message' && item.role === 'user') {
      Row() {
        Column({ space: 4 }) {
          MarkdownView({
            text: TimelineItem.displayText(item),
            onOpenFile: (path: string) => {
              void this.openFilePreview(path);
            }
          })
          if (item.status === 'running' || item.status === 'pending') {
            Text('sending…')
              .fontSize(Theme.fontTiny)
              .fontColor(Theme.userText)
          }
        }
        .padding({ left: 13, right: 13, top: 10, bottom: 10 })
        .backgroundColor(Theme.user)
        .borderRadius(Theme.radiusBubble)
        .constraintSize({ maxWidth: '86%' })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    } else if (item.type === 'message' && item.role === 'assistant') {
      Row() {
        Column() {
          MarkdownView({
            text: TimelineItem.displayText(item),
            onOpenFile: (path: string) => {
              void this.openFilePreview(path);
            }
          })
        }
        .padding({ left: 13, right: 13, top: 10, bottom: 10 })
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.border })
        .borderRadius(Theme.radiusBubble)
        .constraintSize({ maxWidth: '92%' })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    } else if (item.type === 'tool') {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(ToolContent.toolName(item.content))
            .fontSize(Theme.fontSmall)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.code)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .wordBreak(WordBreak.BREAK_ALL)
          Text(item.status)
            .fontSize(Theme.fontTiny)
            .fontColor(this.statusText(item))
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(12)
            .fontColor([Theme.muted])
            .rotate({ angle: this.isToolExpanded(item.id) ? 90 : 0 })
        }
        .width('100%')

        if (this.isToolExpanded(item.id)) {
          if (ToolContent.inputText(item.content).length > 0) {
            Text(ToolContent.inputText(item.content))
              .fontSize(Theme.fontTiny)
              .lineHeight(17)
              .fontColor(Theme.muted)
              .fontFamily('monospace')
              .maxLines(24)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .wordBreak(WordBreak.BREAK_ALL)
              .width('100%')
              .padding(8)
              .backgroundColor(Theme.bg)
              .borderRadius(8)
          }
          if (item.status === 'done' && ToolContent.outputText(item.content).length > 0) {
            Text(ToolContent.outputText(item.content))
              .fontSize(Theme.fontTiny)
              .lineHeight(17)
              .fontColor(Theme.faint)
              .fontFamily('monospace')
              .maxLines(40)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .wordBreak(WordBreak.BREAK_ALL)
              .width('100%')
              .padding(8)
              .backgroundColor(Theme.bg)
              .borderRadius(8)
          }
        } else {
          Text(this.toolSummary(item).length > 0 ? this.toolSummary(item) : 'Tap to expand')
            .fontSize(Theme.fontTiny)
            .fontColor(Theme.muted)
            .fontFamily('monospace')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .wordBreak(WordBreak.BREAK_ALL)
            .width('100%')
        }
      }
      .padding(12)
      .backgroundColor(Theme.surface)
      .border({ width: 1, color: Theme.border })
      .borderRadius(Theme.radiusCard)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .onClick(() => this.toggleTool(item.id))
    } else if (item.type === 'file_change') {
      Column({ space: 6 }) {
        Text(`${FileChangeContent.action(item.content)} ${FileChangeContent.path(item.content)}`.trim() || 'File change')
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.accent)
          .fontFamily('monospace')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_ALL)
          .width('100%')
        if (FileChangeContent.patch(item.content).length > 0) {
          Text(FileChangeContent.patch(item.content))
            .fontSize(Theme.fontTiny)
            .lineHeight(17)
            .fontColor(Theme.muted)
            .fontFamily('monospace')
            .maxLines(12)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .wordBreak(WordBreak.BREAK_ALL)
            .width('100%')
            .padding(8)
            .backgroundColor(Theme.bg)
            .borderRadius(8)
        }
      }
      .padding(12)
      .backgroundColor(Theme.surface)
      .border({ width: 1, color: Theme.border })
      .borderRadius(Theme.radiusCard)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (item.type === 'reasoning') {
      Row({ space: 8 }) {
        Divider()
          .vertical(true)
          .strokeWidth(2)
          .color(Theme.border)
          .height('100%')
        Text(TimelineItem.displayText(item))
          .fontSize(Theme.fontTiny)
          .lineHeight(18)
          .fontColor(Theme.faint)
          .fontStyle(FontStyle.Italic)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_ALL)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: 4, top: 2, bottom: 2 })
    } else if (item.type === 'marker' || item.type === 'system') {
      Text(MarkerContent.title(item.content))
        .fontSize(Theme.fontTiny)
        .fontColor(Theme.faint)
        .textAlign(TextAlign.Center)
        .wordBreak(WordBreak.BREAK_ALL)
        .width('100%')
        .padding(6)
    } else {
      Text(TimelineItem.displayText(item) || item.type)
        .fontSize(Theme.fontTiny)
        .fontColor(Theme.faint)
        .wordBreak(WordBreak.BREAK_ALL)
        .width('100%')
        .padding(6)
    }
  }

  private statusText(item: TimelineItem): ResourceColor {
    return item.status === 'error' || item.status === 'failed' ? Theme.danger : Theme.faint;
  }

  @Builder
  NoticeCard(n: Notice) {
    Column({ space: 8 }) {
      Text(n.title)
        .fontSize(Theme.fontSmall)
        .fontWeight(FontWeight.Medium)
        .fontColor(n.severity === 'error' ? Theme.danger : Theme.text)
        .wordBreak(WordBreak.BREAK_ALL)
        .width('100%')
      if (n.message !== null && (n.message as string).length > 0) {
        Text(n.message as string)
          .fontSize(Theme.fontTiny)
          .lineHeight(18)
          .fontColor(Theme.muted)
          .wordBreak(WordBreak.BREAK_ALL)
          .width('100%')
      }
      // A questionnaire: the questions live in `context.toolInput.questions`,
      // not in `actions` — which only carries Submit/Cancel.
      if (n.questions().length > 0) {
        ForEach(n.questions(), (q: NoticeQuestion) => {
          Column({ space: 8 }) {
            if (q.header.length > 0) {
              Text(q.header)
                .fontSize(Theme.fontTiny)
                .fontColor(Theme.faint)
                .width('100%')
            }
            Text(q.prompt)
              .fontSize(Theme.fontBody)
              .fontColor(Theme.text)
              .wordBreak(WordBreak.BREAK_ALL)
              .width('100%')
            if (q.multiple) {
              Text('可多选')
                .fontSize(Theme.fontTiny)
                .fontColor(Theme.faint)
                .width('100%')
            }
            ForEach(q.options, (o: NoticeQuestionOption) => {
              Row({ space: 10 }) {
                Stack() {
                  Circle({ width: 18, height: 18 })
                    .fill(this.isPicked(n.noticeId, q.questionId, o.optionId)
                      ? Theme.accent : Color.Transparent)
                    .stroke(Theme.border)
                    .strokeWidth(1)
                  if (this.isPicked(n.noticeId, q.questionId, o.optionId)) {
                    Circle({ width: 7, height: 7 }).fill(Theme.onAccent)
                  }
                }
                .width(18)
                .height(18)

                Column({ space: 2 }) {
                  Text(o.label)
                    .fontSize(Theme.fontSmall)
                    .fontColor(Theme.text)
                    .width('100%')
                  if (o.description !== null && (o.description as string).length > 0) {
                    Text(o.description as string)
                      .fontSize(Theme.fontTiny)
                      .fontColor(Theme.muted)
                      .wordBreak(WordBreak.BREAK_ALL)
                      .width('100%')
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 10, bottom: 10 })
              .backgroundColor(this.isPicked(n.noticeId, q.questionId, o.optionId)
                ? Theme.accentTint : Theme.raised)
              .borderRadius(10)
              .onClick(() => this.togglePick(n.noticeId, q, o.optionId))
            }, (o: NoticeQuestionOption) => `${q.questionId}-${o.optionId}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (q: NoticeQuestion) => `${n.noticeId}-${q.questionId}`)

        Row({ space: 8 }) {
          Button('取消')
            .fontSize(Theme.fontTiny)
            .height(32)
            .backgroundColor(Theme.raised)
            .fontColor(Theme.muted)
            .borderRadius(Theme.radiusPill)
            .onClick(() => this.respond(n.noticeId, 'cancel'))
          Button('提交')
            .fontSize(Theme.fontTiny)
            .height(32)
            .enabled(this.answersComplete(n.noticeId, n.questions()))
            .backgroundColor(Theme.accent)
            .fontColor(Theme.onAccent)
            .borderRadius(Theme.radiusPill)
            .opacity(this.answersComplete(n.noticeId, n.questions()) ? 1 : 0.4)
            .onClick(() => this.submitAnswers(n))
        }
      } else {
        Row({ space: 8 }) {
          ForEach(n.actions, (a: NoticeAction) => {
            Button(a.label)
              .fontSize(Theme.fontTiny)
              .height(32)
              .backgroundColor(a.style === 'danger' ? Theme.danger : Theme.accent)
              .fontColor(a.style === 'danger' ? '#FFFFFF' : Theme.onAccent)
              .borderRadius(Theme.radiusPill)
              .onClick(() => this.respond(n.noticeId, a.actionId))
          }, (a: NoticeAction) => `${n.noticeId}-${a.actionId}`)
        }
      }
    }
    .padding(12)
    .backgroundColor(n.severity === 'error' ? Theme.dangerSurface : Theme.surface)
    .border({ width: 1, color: n.severity === 'error' ? Theme.danger : Theme.border })
    .borderRadius(Theme.radiusCard)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
