/**
 * Typed request bodies. ArkTS forbids passing untyped object literals
 * (`arkts-no-untyped-obj-literals`), so every JSON request body is a declared class.
 */

export class PasswordSaltRequest {
  email: string = '';
}

export class LoginRequest {
  email: string = '';
  passwordVerifier: string = '';
}

export class BulkActionRequest {
  sessionIds: Array<string> = [];
}

/**
 * `PATCH /sessions/{id}/meta`. Every field is nullable because the server reads
 * null as "leave alone": sending both booleans on a pin would clear `archived`.
 */
export class SessionMetaPatch {
  title: string | null = null;
  pinned: boolean | null = null;
  archived: boolean | null = null;
}

/**
 * `POST /sessions/create-and-start`. The server forbids extra fields, so only
 * the ones it requires are declared — the rest have defaults there.
 */
export class CreateAndStartRequest {
  connectorId: string = '';
  projectId: string = '';
  runtime: string = '';
  content: string = '';
}

export class MessageSendRequest {
  content: string = '';
  attachments: Array<Object> = [];
  clientMessageId: string = '';
}

/**
 * `PATCH /sessions/{id}/runtime/selections`. Model and permission are their own
 * endpoint — the server rejects extra fields on the message body.
 */
export class SelectionPatchRequest {
  selections: Record<string, string> = {};
}

export class NoticeRespondRequest {
  actionId: string = '';
}

export class WsTicketScope {
  sessionId: string | null = null;
  dashboard: boolean = false;
}

export class WsTicketRequest {
  clientId: string = '';
  scope: WsTicketScope = new WsTicketScope();
}

export class MobileLoginRequest {
  userId: string = '';
  loginToken: string = '';
  deviceName: string = '';
}

export class MobileLoginConfirmRequest {
  loginToken: string = '';
  approved: boolean = true;
}

export class MobileLoginStatusRequest {
  loginToken: string = '';
}

export class MobileLoginExchangeRequest {
  userId: string = '';
  loginToken: string = '';
}

/** Empty JSON body for POST/DELETE calls that take no payload. */
export class EmptyBody {
}

export class FileReadRequest {
  path: string = '';
  maxBytes: number = 1048576;
}

export class AttachmentRef {
  fileId: string = '';
}
