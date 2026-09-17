// SPDX-License-Identifier: AGPL-3.0-only
import { ApiError } from './errors';

/** Fastify's default body limit, and the relay's for everything but /share. */
export const DEFAULT_BODY_LIMIT = 1024 * 1024;
/** /share carries a 2 MB GPX plus its JSON escaping overhead. */
export const SHARE_BODY_LIMIT = 3 * 1024 * 1024;

const TOO_LARGE = 'Request body is too large.';
const REQUIRED = 'A JSON request body is required.';
const NOT_JSON = 'Request body is not valid JSON.';

function isJsonContentType(value: string | null): boolean {
  if (value === null) return false;
  const type = value.split(';', 1)[0]?.trim().toLowerCase() ?? '';
  return type === 'application/json' || type.endsWith('+json');
}

/**
 * Read and parse a JSON request body, refusing anything over `limit` bytes.
 *
 * The limit is checked twice on purpose: `content-length` catches the honest
 * caller before a single byte is buffered, and the streamed accumulation
 * catches a chunked body that lied about (or omitted) its length. Passing the
 * limit cancels the stream rather than draining it.
 *
 * The four failure messages are the ones the Fastify relay produced.
 */
export async function readJsonBody(
  request: Request,
  limit: number = DEFAULT_BODY_LIMIT,
): Promise<unknown> {
  if (!isJsonContentType(request.headers.get('content-type'))) {
    throw new ApiError('invalid_request', REQUIRED);
  }

  const declared = request.headers.get('content-length');
  if (declared !== null) {
    const length = Number(declared);
    if (Number.isFinite(length) && length > limit) {
      throw new ApiError('invalid_request', TOO_LARGE);
    }
  }

  const body = request.body;
  let text: string;
  if (body === null) {
    text = '';
  } else {
    const reader = body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value === undefined) continue;
      total += value.byteLength;
      if (total > limit) {
        await reader.cancel().catch(() => undefined);
        throw new ApiError('invalid_request', TOO_LARGE);
      }
      chunks.push(value);
    }
    const joined = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      joined.set(chunk, offset);
      offset += chunk.byteLength;
    }
    text = new TextDecoder().decode(joined);
  }

  if (text.trim() === '') {
    throw new ApiError('invalid_request', REQUIRED);
  }
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new ApiError('invalid_request', NOT_JSON);
  }
}
