import { AuthUser } from './model/Auth';
import { ConnectorView } from './model/Connector';
import { SessionView } from './model/Session';
import { Prefs } from './store/Prefs';

/**
 * 演示模式: a sample account with no server behind it.
 *
 * Two reasons it exists. AppGallery reviewers need to get past the login screen
 * without credentials, and store screenshots have to be taken without exposing
 * the operator's real projects. Everything shown here is invented.
 */
export class Demo {
  static on(): boolean {
    return Prefs.getBool(Prefs.keys.demoMode, false);
  }

  static enter(): void {
    Prefs.putBool(Prefs.keys.demoMode, true);
  }

  static exit(): void {
    Prefs.putBool(Prefs.keys.demoMode, false);
  }

  static readonly serverUrl: string = '演示模式 · 不连接服务器';
  static readonly displayName: string = '演示账号';
  static readonly email: string = 'demo@example.com';

  static user(): AuthUser {
    const u = new AuthUser();
    u.userId = 'demo';
    u.displayName = Demo.displayName;
    u.email = Demo.email;
    u.role = 'demo';
    return u;
  }

  private static minutesAgo(m: number): string {
    return new Date(Date.now() - m * 60000).toISOString();
  }

  static readonly CONNECTOR_STUDIO: string = 'conn_demo_studio';
  static readonly CONNECTOR_LAPTOP: string = 'conn_demo_laptop';

  private static make(
    id: string, title: string, cwd: string, projectId: string,
    status: string, online: boolean, minutes: number,
    unread: boolean, pinned: boolean
  ): SessionView {
    const s = new SessionView();
    s.id = id;
    s.title = title;
    s.cwd = cwd;
    s.projectId = projectId;
    s.runtime = 'claude';
    s.connectorId = online ? Demo.CONNECTOR_STUDIO : Demo.CONNECTOR_LAPTOP;
    s.connectorStatus = online ? 'online' : 'offline';
    s.status = status;
    s.unread = unread;
    s.pinned = pinned;
    s.gitBranch = status === 'running' ? 'feat/audit-pagination' : 'main';
    s.lastActivityAt = Demo.minutesAgo(minutes);
    s.lastItemAt = s.lastActivityAt;
    s.updatedSeq = 900 - minutes;
    return s;
  }

  static sessions(): Array<SessionView> {
    const orbit = '/Users/dev/Projects/orbit-api';
    const orbitWt = '/Users/dev/Projects/orbit-api/.claude/worktrees/serene-curie-2f91ac';
    const atlas = '/Users/dev/Projects/atlas-web';
    const nimbus = '/Users/dev/Projects/nimbus-infra';
    return [
      Demo.make('s1', 'Add pagination to the audit log endpoint', orbitWt, 'p1',
        'running', true, 2, false, false),
      Demo.make('s2', 'Extract the retry policy into a shared helper', orbitWt, 'p1',
        'waiting_approval', true, 14, false, false),
      Demo.make('s3', 'Fix the flaky snapshot test in the scheduler', orbit, 'p1',
        'idle', true, 60, true, false),
      Demo.make('s4', 'Review the migration for the events table', atlas, 'p2',
        'pending', true, 180, false, false),
      Demo.make('s5', 'Investigate slow cold start on the worker', atlas, 'p2',
        'idle', false, 300, false, true),
      Demo.make('s6', 'Document the connector handshake', nimbus, 'p3',
        'error', true, 1500, false, false),
      Demo.make('s7', 'Bump the SDK and fix the breaking changes', nimbus, 'p3',
        'idle', true, 2900, false, false)
    ];
  }

  static connectors(): Array<ConnectorView> {
    const studio = new ConnectorView();
    studio.id = Demo.CONNECTOR_STUDIO;
    studio.name = 'Studio Mac';
    studio.machine = 'studio-mac';
    studio.status = 'online';
    studio.online = true;
    studio.deviceOs = 'macos';
    studio.connectorKind = 'desktop';
    studio.lastSeenAt = new Date().toISOString();
    studio.runtimeCount = 2;
    studio.workspaceCount = 3;

    const build = new ConnectorView();
    build.id = 'conn_demo_build';
    build.name = 'Build Box';
    build.machine = 'build-01';
    build.status = 'online';
    build.online = true;
    build.deviceOs = 'linux';
    build.connectorKind = 'headless';
    build.lastSeenAt = new Date().toISOString();
    build.runtimeCount = 1;
    build.workspaceCount = 1;

    const laptop = new ConnectorView();
    laptop.id = Demo.CONNECTOR_LAPTOP;
    laptop.name = 'Old Laptop';
    laptop.machine = 'thinkpad';
    laptop.status = 'offline';
    laptop.online = false;
    laptop.deviceOs = 'windows';
    laptop.connectorKind = 'desktop';
    laptop.lastSeenAt = Demo.minutesAgo(320);
    laptop.runtimeCount = 1;
    laptop.workspaceCount = 2;

    return [studio, build, laptop];
  }

  /**
   * Snapshot for the detail page. Kept as JSON text because `Snapshot.fromJson`
   * already reads this shape and ArkTS has no untyped object literals.
   */
  static snapshot(): Object {
    return JSON.parse(`{
      "session": {
        "id": "s1",
        "title": "Add pagination to the audit log endpoint",
        "runtime": "claude",
        "connectorId": "${Demo.CONNECTOR_STUDIO}",
        "connectorStatus": "online",
        "cwd": "/Users/dev/Projects/orbit-api/.claude/worktrees/serene-curie-2f91ac",
        "gitBranch": "feat/audit-pagination",
        "status": "running",
        "takeover": true,
        "pinned": false,
        "unread": false,
        "archived": false
      },
      "timeline": {
        "nextSeq": 6,
        "items": [
          {
            "id": "t1", "type": "message", "role": "user", "status": "done",
            "orderSeq": 1, "updatedSeq": 1,
            "content": { "text": "The audit log endpoint returns everything in one page. Add cursor pagination with a default page size of 50, and keep the existing response shape for clients that do not send a cursor." }
          },
          {
            "id": "t2", "type": "reasoning", "status": "done",
            "orderSeq": 2, "updatedSeq": 2,
            "content": { "summary": "The endpoint currently streams every row. Old callers have to keep working, so the cursor has to be optional and the default response has to stay identical." }
          },
          {
            "id": "t3", "type": "message", "role": "assistant", "status": "done",
            "orderSeq": 3, "updatedSeq": 3,
            "content": { "text": "I will build the cursor from (createdAt, id) so it stays stable across inserts, and leave the response shape untouched when no cursor is supplied." }
          },
          {
            "id": "t4", "type": "tool", "status": "done",
            "orderSeq": 4, "updatedSeq": 4,
            "content": {
              "name": "Read",
              "input": { "file": "app/api/audit.py" },
              "output": "def list_audit(...): rows = db.execute(select(AuditLog))"
            }
          },
          {
            "id": "t5", "type": "message", "role": "assistant", "status": "running",
            "orderSeq": 5, "updatedSeq": 5,
            "content": { "text": "Now updating the query. Keeping createdAt in the cursor so rows written while a client is paging cannot shift the window." }
          }
        ]
      },
      "notices": [],
      "serverTime": ""
    }`);
  }
}
