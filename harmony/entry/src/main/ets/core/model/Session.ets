import { Json } from '../util/Json';

export type SessionStatus =
  'idle' | 'waiting' | 'pending' | 'running' | 'stopping' | 'waiting_approval' | 'error' | 'blocked';

export class SessionView {
  id: string = '';
  title: string | null = null;
  runtime: string = 'unknown';
  /**
   * The runtime *instance* on the connector. `runtime` above is only the type,
   * and a connector can host several instances of one type, so anything that
   * addresses a runtime (create, start, catalog) has to send this instead.
   */
  runtimeId: string = '';
  connectorId: string = '';
  connectorStatus: string = 'offline';
  cwd: string | null = null;
  gitBranch: string | null = null;
  externalSessionId: string | null = null;
  projectId: string | null = null;
  status: string = 'idle';
  takeover: boolean = false;
  pinned: boolean = false;
  unread: boolean = false;
  archived: boolean = false;
  lastActivityAt: string | null = null;
  lastItemAt: string | null = null;
  updatedSeq: number = 0;
  sourceAvailability: string = 'unknown';

  static fromJson(o: Object | null): SessionView {
    const s = new SessionView();
    s.id = Json.strOr(o, 'id', '');
    s.title = Json.str(o, 'title');
    s.runtime = Json.strOr(o, 'runtime', 'unknown');
    s.runtimeId = Json.strOr(o, 'runtimeId', s.runtime);
    s.connectorId = Json.strOr(o, 'connectorId', '');
    s.connectorStatus = Json.strOr(o, 'connectorStatus', 'offline');
    s.cwd = Json.str(o, 'cwd');
    s.gitBranch = Json.str(o, 'gitBranch');
    s.externalSessionId = Json.str(o, 'externalSessionId');
    s.projectId = Json.str(o, 'projectId');
    s.status = Json.strOr(o, 'status', 'idle');
    s.takeover = Json.bool(o, 'takeover') ?? false;
    s.pinned = Json.bool(o, 'pinned') ?? false;
    s.unread = Json.bool(o, 'unread') ?? false;
    s.archived = Json.bool(o, 'archived') ?? false;
    s.lastActivityAt = Json.str(o, 'lastActivityAt');
    s.lastItemAt = Json.str(o, 'lastItemAt');
    s.updatedSeq = Json.numOr(o, 'updatedSeq', 0);
    s.sourceAvailability = Json.strOr(o, 'sourceAvailability', 'unknown');
    return s;
  }
}

export class SessionListResponse {
  sessions: Array<SessionView> = [];
  hasMore: boolean = false;
  nextCursor: string | null = null;

  static fromJson(o: Object | null): SessionListResponse {
    const r = new SessionListResponse();
    r.sessions = (Json.arr(o, 'sessions') ?? []).map((raw: Object) => SessionView.fromJson(raw));
    r.hasMore = Json.bool(o, 'hasMore') ?? false;
    r.nextCursor = Json.str(o, 'nextCursor');
    return r;
  }
}

export class TimelineItem {
  id: string = '';
  sessionId: string = '';
  type: string = 'unknown';
  status: string = 'unknown';
  role: string | null = null;
  orderSeq: number = 0;
  revision: number = 1;
  updatedSeq: number = 0;
  contentHash: string = '';
  createdAt: string = '';
  updatedAt: string = '';
  completedAt: string | null = null;
  /** Raw JSON, kept for tool/file-change rendering. Null-tolerant accessors read it. */
  content: Object | null = null;

  /** Text shown in the timeline: message body, reasoning summary, marker title. */
  static displayText(item: TimelineItem): string {
    switch (item.type) {
      case 'message':
        return MessageContent.text(item.content);
      case 'reasoning':
        return Json.strOr(item.content, 'summary', '') || Json.strOr(item.content, 'text', '');
      case 'marker':
      case 'system':
      case 'turn.start':
      case 'turn.end':
        return MarkerContent.title(item.content);
      case 'tool':
        return ToolContent.toolName(item.content);
      case 'file_change':
        return FileChangeContent.path(item.content);
      default:
        return '';
    }
  }

  static fromJson(o: Object | null): TimelineItem {
    const t = new TimelineItem();
    t.id = Json.strOr(o, 'id', '');
    t.sessionId = Json.strOr(o, 'sessionId', '');
    t.type = Json.strOr(o, 'type', 'unknown');
    t.status = Json.strOr(o, 'status', 'unknown');
    t.role = Json.str(o, 'role');
    t.updatedSeq = Json.numOr(o, 'updatedSeq', 0);
    t.orderSeq = Json.num(o, 'orderSeq') ?? t.updatedSeq;
    t.contentHash = Json.strOr(o, 'contentHash', '');
    t.createdAt = Json.strOr(o, 'createdAt', '');
    t.updatedAt = Json.str(o, 'updatedAt') ?? t.createdAt;
    t.completedAt = Json.str(o, 'completedAt');
    t.content = Json.obj(o, 'content');
    return t;
  }
}

export class MessageContent {
  static text(content: Object | null): string {
    const keys: Array<string> = ['text', 'content', 'message', 'rawText'];
    for (const k of keys) {
      const v = Json.str(content, k);
      if (v !== null && v.length > 0) {
        return v;
      }
    }
    return '';
  }

  static attachments(content: Object | null): Array<Object> {
    return Json.arr(content, 'attachments') ?? [];
  }
}

export class ToolContent {
  static toolName(content: Object | null): string {
    return Json.str(content, 'name') ?? Json.str(content, 'toolName') ?? 'Tool';
  }

  static inputText(content: Object | null): string {
    const input = Json.obj(content, 'input');
    if (input === null) {
      return '';
    }
    return ToolContent.pretty(input);
  }

  static outputText(content: Object | null): string {
    const output = Json.obj(content, 'output');
    if (output === null) {
      return '';
    }
    return ToolContent.pretty(output);
  }

  private static pretty(v: Object): string {
    try {
      return JSON.stringify(v);
    } catch (e) {
      return '';
    }
  }
}

export class FileChangeContent {
  static path(content: Object | null): string {
    return Json.str(content, 'path') ?? '';
  }

  static action(content: Object | null): string {
    return Json.str(content, 'action') ?? '';
  }

  static patch(content: Object | null): string {
    return Json.str(content, 'patch') ?? '';
  }
}

export class MarkerContent {
  static title(content: Object | null): string {
    return Json.str(content, 'title') ?? Json.str(content, 'text') ?? 'Event';
  }

  static subtitle(content: Object | null): string {
    return Json.str(content, 'subtitle') ?? Json.str(content, 'description') ?? '';
  }
}

export class NoticeAction {
  actionId: string = '';
  label: string = '';
  style: string = 'secondary';

  static fromJson(o: Object | null): NoticeAction {
    const a = new NoticeAction();
    a.actionId = Json.strOr(o, 'actionId', '');
    a.label = Json.strOr(o, 'label', a.actionId);
    a.style = Json.strOr(o, 'style', 'secondary');
    return a;
  }
}

export class NoticeQuestionOption {
  optionId: string = '';
  label: string = '';
  description: string | null = null;
}

export class NoticeQuestion {
  questionId: string = '';
  header: string = '';
  prompt: string = '';
  multiple: boolean = false;
  options: Array<NoticeQuestionOption> = [];
}

export class Notice {
  noticeId: string = '';
  sessionId: string = '';
  title: string = 'Notice';
  message: string | null = null;
  type: string = 'interaction';
  severity: string = 'info';
  status: string = 'open';
  responseRequired: boolean = false;
  interactionType: string | null = null;
  actions: Array<NoticeAction> = [];
  /**
   * Runtime payload. For an `input_request` this is where the real questions
   * live — `context.toolInput.questions` — while `actions` only carries the
   * Submit/Cancel buttons. Dropping it left every questionnaire rendered as
   * raw JSON.
   */
  context: Object | null = null;

  /**
   * The questions behind an `input_request`, or an empty list.
   *
   * Ids are derived by position (`q_<i>` / `o_<j>`) to match the connector's
   * own scheme; the submit payload is keyed by them.
   */
  questions(): Array<NoticeQuestion> {
    const input = Json.obj(this.context, 'toolInput');
    const raw = Json.arr(input, 'questions') ?? [];
    const out: Array<NoticeQuestion> = [];
    for (let i = 0; i < raw.length; i++) {
      const q = raw[i];
      const item = new NoticeQuestion();
      item.questionId = `q_${i}`;
      item.prompt = Json.strOr(q, 'question', '');
      item.header = Json.strOr(q, 'header', '');
      item.multiple = Json.bool(q, 'multiSelect') ?? false;
      const rawOptions = Json.arr(q, 'options') ?? [];
      for (let j = 0; j < rawOptions.length; j++) {
        const o = rawOptions[j];
        const option = new NoticeQuestionOption();
        option.optionId = `o_${j}`;
        option.label = Json.strOr(o, 'label', '');
        option.description = Json.str(o, 'description');
        item.options.push(option);
      }
      out.push(item);
    }
    return out;
  }

  static fromJson(o: Object | null): Notice {
    const n = new Notice();
    n.noticeId = Json.strOr(o, 'noticeId', '');
    n.sessionId = Json.strOr(o, 'sessionId', '');
    n.title = Json.strOr(o, 'title', 'Notice');
    n.message = Json.str(o, 'message');
    n.type = Json.strOr(o, 'type', 'interaction');
    n.severity = Json.strOr(o, 'severity', 'info');
    n.status = Json.strOr(o, 'status', 'open');
    n.responseRequired = Json.bool(o, 'responseRequired') ?? false;
    n.interactionType = Json.str(o, 'interactionType');
    n.actions = (Json.arr(o, 'actions') ?? []).map((raw: Object) => NoticeAction.fromJson(raw));
    n.context = Json.obj(o, 'context');
    return n;
  }
}

export class Snapshot {
  session: SessionView = new SessionView();
  timeline: Array<TimelineItem> = [];
  nextSeq: number = 0;
  notices: Array<Notice> = [];
  serverTime: string = '';

  static fromJson(o: Object | null): Snapshot {
    const s = new Snapshot();
    s.session = SessionView.fromJson(Json.obj(o, 'session'));
    const timeline = Json.obj(o, 'timeline');
    s.timeline = (Json.arr(timeline, 'items') ?? []).map((raw: Object) => TimelineItem.fromJson(raw));
    s.nextSeq = Json.numOr(timeline, 'nextSeq', 0);
    s.notices = (Json.arr(o, 'notices') ?? []).map((raw: Object) => Notice.fromJson(raw));
    s.serverTime = Json.strOr(o, 'serverTime', '');
    return s;
  }
}
