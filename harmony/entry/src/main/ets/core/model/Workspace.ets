import { Json } from '../util/Json';

/** One directory entry from the connector's `fs.readDir`. */
export class FsEntry {
  name: string = '';
  path: string = '';
  /** `directory` | `file` | `other` */
  type: string = 'file';
  size: number = 0;
  isDirectory: boolean = false;

  static fromJson(o: Object | null): FsEntry {
    const e = new FsEntry();
    e.name = Json.strOr(o, 'name', '');
    e.path = Json.strOr(o, 'path', '');
    e.type = Json.strOr(o, 'type', 'file');
    e.size = Json.numOr(o, 'size', 0);
    e.isDirectory = e.type === 'directory';
    return e;
  }
}

export class FsListResult {
  path: string = '';
  entries: Array<FsEntry> = [];
  truncated: boolean = false;

  static fromJson(o: Object | null): FsListResult {
    const r = new FsListResult();
    r.path = Json.strOr(o, 'path', '');
    r.entries = (Json.arr(o, 'entries') ?? []).map((raw: Object) => FsEntry.fromJson(raw));
    r.truncated = Json.bool(o, 'truncated') ?? false;
    return r;
  }
}

/** `POST /connectors/{id}/fs/list` body. */
export class FsPathRequest {
  path: string = '.';
}

export class ShellExecRequest {
  command: string = '';
  cwd: string | null = null;
  timeoutMs: number = 60000;
}

export class ShellExecResult {
  stdout: string = '';
  stderr: string = '';
  exitCode: number = 0;

  static fromJson(o: Object | null): ShellExecResult {
    const r = new ShellExecResult();
    r.stdout = Json.strOr(o, 'stdout', '');
    r.stderr = Json.strOr(o, 'stderr', '');
    r.exitCode = Json.numOr(o, 'exitCode', 0);
    return r;
  }
}

/** Route parameter for the Workspace nav destination. */
export class WorkspaceParam {
  connectorId: string = '';
  /** Session cwd — the workspace root every fs/shell call is scoped to. */
  root: string = '';
  title: string = '';
}
