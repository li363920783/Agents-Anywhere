import { Json } from '../util/Json';

export class ModelItem {
  displayName: string = '';
  id: string = '';
  selectionId: string = '';
  description: string = '';
  isDefault: boolean = false;

  static fromJson(o: Object | null): ModelItem {
    const m = new ModelItem();
    m.displayName = Json.strOr(o, 'displayName', '');
    m.id = Json.strOr(o, 'id', '');
    m.selectionId = Json.strOr(o, 'selectionId', '');
    m.description = Json.strOr(o, 'description', '');
    m.isDefault = Json.bool(o, 'default') === true;
    return m;
  }
}

export class ModelCatalog {
  runtime: string = '';
  revision: number = 0;
  models: Array<ModelItem> = [];

  static fromJson(o: Object | null): ModelCatalog {
    const c = new ModelCatalog();
    c.runtime = Json.strOr(o, 'runtime', '');
    c.revision = Json.numOr(o, 'revision', 0);
    c.models = (Json.arr(o, 'models') ?? []).map((raw: Object) => ModelItem.fromJson(raw));
    return c;
  }
}

export class PermissionItem {
  displayName: string = '';
  id: string = '';
  selectionId: string = '';
  description: string = '';
  isDefault: boolean = false;

  static fromJson(o: Object | null): PermissionItem {
    const p = new PermissionItem();
    p.displayName = Json.strOr(o, 'displayName', '');
    p.id = Json.strOr(o, 'id', '');
    p.selectionId = Json.strOr(o, 'selectionId', '');
    p.description = Json.strOr(o, 'description', '');
    p.isDefault = Json.bool(o, 'default') === true;
    return p;
  }
}

export class PermissionCatalog {
  runtime: string = '';
  revision: number = 0;
  permissions: Array<PermissionItem> = [];

  static fromJson(o: Object | null): PermissionCatalog {
    const c = new PermissionCatalog();
    c.runtime = Json.strOr(o, 'runtime', '');
    c.revision = Json.numOr(o, 'revision', 0);
    c.permissions = (Json.arr(o, 'permissions') ?? []).map((raw: Object) => PermissionItem.fromJson(raw));
    return c;
  }
}

export class TextFile {
  path: string = '';
  name: string = '';
  size: number = 0;
  content: string = '';
  binary: boolean = false;
  truncated: boolean = false;

  static fromJson(o: Object | null): TextFile {
    const f = new TextFile();
    f.path = Json.strOr(o, 'path', '');
    f.name = Json.strOr(o, 'name', '');
    f.size = Json.numOr(o, 'size', 0);
    f.content = Json.strOr(o, 'content', '');
    f.binary = Json.bool(o, 'binary') === true;
    f.truncated = Json.bool(o, 'truncated') === true;
    return f;
  }
}
