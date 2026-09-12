// SPDX-License-Identifier: AGPL-3.0-only
import type { FastifyReply } from 'fastify';

/**
 * Minimal Server-Sent Events writer.
 *
 * Fastify's reply is hijacked so we own the raw socket: the AI routes stream
 * for tens of seconds and must be able to flush partial output.
 */
export class SseStream {
  #closed = false;
  readonly #raw: NodeJS.WritableStream;

  constructor(reply: FastifyReply, requestId: string) {
    reply.hijack();
    const raw = reply.raw;
    raw.writeHead(200, {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      // Tell nginx-style proxies not to buffer the stream.
      'x-accel-buffering': 'no',
      'x-request-id': requestId,
    });
    // A first comment frame makes proxies commit the response headers.
    raw.write(': open\n\n');
    this.#raw = raw;
  }

  get closed(): boolean {
    return this.#closed;
  }

  /** Write one named event with a JSON data payload. */
  send(event: string, data: unknown): void {
    if (this.#closed) return;
    const payload = JSON.stringify(data ?? {});
    this.#raw.write(`event: ${event}\ndata: ${payload}\n\n`);
  }

  end(): void {
    if (this.#closed) return;
    this.#closed = true;
    this.#raw.end();
  }
}
