// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { DEFAULT_BODY_LIMIT, readJsonBody } from '@/server/body';
import { ApiError } from '@/server/errors';

const URL = 'https://api.velorki.com/share';

function request(body: BodyInit | null, headers: Record<string, string> = {}): Request {
  return new Request(URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    ...(body === null ? {} : { body }),
  });
}

async function rejection(req: Request, limit?: number): Promise<ApiError> {
  try {
    await readJsonBody(req, limit);
  } catch (err) {
    expect(err).toBeInstanceOf(ApiError);
    return err as ApiError;
  }
  throw new Error('readJsonBody resolved but should have thrown');
}

describe('readJsonBody', () => {
  it('parses a JSON body', async () => {
    await expect(readJsonBody(request(JSON.stringify({ a: 1 })))).resolves.toEqual({ a: 1 });
  });

  it('accepts a charset parameter on the content type', async () => {
    await expect(
      readJsonBody(request('{"a":1}', { 'content-type': 'application/json; charset=utf-8' })),
    ).resolves.toEqual({ a: 1 });
  });

  it('refuses an over-sized content-length before the body is parsed', async () => {
    // An empty stream: without the content-length check this would fail with
    // "A JSON request body is required." instead.
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.close();
      },
    });
    const req = new Request(URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'content-length': '999999' },
      body: stream,
      // @ts-expect-error undici needs this for a streaming request body
      duplex: 'half',
    });
    const err = await rejection(req, 1024);
    expect(err.status).toBe(400);
    expect(err.code).toBe('invalid_request');
    expect(err.message).toBe('Request body is too large.');
  });

  it('refuses and cancels a streamed body that passes the limit', async () => {
    let cancelled = false;
    const chunk = new TextEncoder().encode('x'.repeat(256));
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        controller.enqueue(chunk);
      },
      cancel() {
        cancelled = true;
      },
    });
    const req = new Request(URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: stream,
      // @ts-expect-error undici needs this for a streaming request body
      duplex: 'half',
    });

    const err = await rejection(req, 1024);
    expect(err.message).toBe('Request body is too large.');
    expect(cancelled).toBe(true);
  });

  it('refuses an empty body', async () => {
    expect((await rejection(request(''))).message).toBe('A JSON request body is required.');
    expect((await rejection(request('   '))).message).toBe('A JSON request body is required.');
    expect((await rejection(request(null))).message).toBe('A JSON request body is required.');
  });

  it('refuses a body that is not JSON', async () => {
    expect((await rejection(request('not json at all'))).message).toBe(
      'Request body is not valid JSON.',
    );
  });

  it('refuses the wrong content type', async () => {
    expect(
      (await rejection(request('{"a":1}', { 'content-type': 'text/plain' }))).message,
    ).toBe('A JSON request body is required.');
    expect(
      (
        await rejection(
          new Request(URL, { method: 'POST', body: 'a=1' }),
        )
      ).message,
    ).toBe('A JSON request body is required.');
  });

  it("defaults to Fastify's 1 MB limit", async () => {
    expect(DEFAULT_BODY_LIMIT).toBe(1024 * 1024);
    const err = await rejection(
      request(JSON.stringify({ blob: 'x'.repeat(DEFAULT_BODY_LIMIT) })),
    );
    expect(err.message).toBe('Request body is too large.');
  });
});
