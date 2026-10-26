import { Json } from '../util/Json';

/** Connector / device models (read surface used by the Devices page). */
export class ConnectorView {
  id: string = '';
  name: string = '';
  machine: string = '';
  /** Server-reported presence; the list endpoint sends `status`, not a boolean. */
  status: string = 'offline';
  online: boolean = false;
  deviceOs: string = '';
  connectorKind: string = '';
  lastSeenAt: string | null = null;
  runtimeCount: number = 0;
  workspaceCount: number = 0;

  static fromJson(o: Object | null): ConnectorView {
    const c = new ConnectorView();
    c.id = Json.strOr(o, 'id', '');
    c.name = Json.str(o, 'name') ?? c.id;
    c.machine = Json.str(o, 'machine') ?? Json.str(o, 'hostname') ?? '';
    c.status = Json.strOr(o, 'status', Json.bool(o, 'online') === true ? 'online' : 'offline');
    c.online = c.status === 'online';
    c.deviceOs = Json.strOr(o, 'deviceOs', '');
    c.connectorKind = Json.strOr(o, 'connectorKind', '');
    c.lastSeenAt = Json.str(o, 'lastSeenAt');
    c.runtimeCount = Json.numOr(o, 'runtimeCount', 0);
    c.workspaceCount = Json.numOr(o, 'workspaceCount', 0);
    return c;
  }
}

export class ConnectorListResponse {
  connectors: Array<ConnectorView> = [];

  static fromJson(o: Object | null): ConnectorListResponse {
    const r = new ConnectorListResponse();
    r.connectors = (Json.arr(o, 'connectors') ?? []).map((raw: Object) => ConnectorView.fromJson(raw));
    return r;
  }
}
