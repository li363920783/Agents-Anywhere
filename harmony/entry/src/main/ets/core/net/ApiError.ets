/** Transport-level error carrying the HTTP status and raw body. */
export class ApiError extends Error {
  public readonly httpCode: number;
  public readonly body: string;

  constructor(httpCode: number, message: string, body: string) {
    super(message);
    this.name = 'ApiError';
    this.httpCode = httpCode;
    this.body = body;
  }
}
