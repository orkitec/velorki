// SPDX-License-Identifier: AGPL-3.0-only

/**
 * Server-Sent Events as a streaming `Response`.
 *
 * The headers, the `: open` preamble and the frame format are byte-identical to
 * the Fastify relay's hijacked socket. Two things keep a long run alive and
 * cheap: a `: ping` comment every 20 s (Cloudflare drops an idle connection at
 * 100 s), and an abort path so that a rider closing the app stops the model
 * call instead of paying for tokens nobody will read.
 */

export const PING_INTERVAL_MS = 20_000;

export interface SseWriter {
  /** Write one named event with a JSON data payload. */
  send(event: string, data: unknown): void;
  readonly closed: boolean;
}

export interface SseOptions {
  requestId: string;
  /** `request.signal`: fires when the client disconnects. */
  signal?: AbortSignal;
  /**
   * The body of the stream. `signal` is aborted when the client goes away or
   * the stream is cancelled; pass it to the model call.
   */
  run: (sse: SseWriter, signal: AbortSignal) => Promise<void>;
}

export function sseResponse(opts: SseOptions): Response {
  const encoder = new TextEncoder();
  const abort = new AbortController();
  let ping: ReturnType<typeof setInterval> | undefined;
  let closed = false;

  const cleanup = (): void => {
    closed = true;
    if (ping !== undefined) {
      clearInterval(ping);
      ping = undefined;
    }
  };

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const write = (chunk: string): void => {
        if (closed) return;
        try {
          controller.enqueue(encoder.encode(chunk));
        } catch {
          // The consumer went away between the check and the enqueue.
          cleanup();
        }
      };

      // A first comment frame makes proxies commit the response headers.
      write(': open\n\n');

      ping = setInterval(() => {
        write(': ping\n\n');
      }, PING_INTERVAL_MS);
      // Never let the keep-alive timer hold the process open on shutdown.
      (ping as unknown as { unref?: () => void }).unref?.();

      const onAbort = (): void => {
        abort.abort();
      };
      if (opts.signal !== undefined) {
        if (opts.signal.aborted) abort.abort();
        else opts.signal.addEventListener('abort', onAbort, { once: true });
      }

      const writer: SseWriter = {
        send(event, data) {
          write(`event: ${event}\ndata: ${JSON.stringify(data ?? {})}\n\n`);
        },
        get closed() {
          return closed;
        },
      };

      void opts
        .run(writer, abort.signal)
        .catch(() => undefined)
        .finally(() => {
          opts.signal?.removeEventListener('abort', onAbort);
          cleanup();
          try {
            controller.close();
          } catch {
            // Already closed by a cancel().
          }
        });
    },

    cancel() {
      // The reader gave up: stop the run and the pings.
      abort.abort();
      cleanup();
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      // Tell nginx-style proxies not to buffer the stream.
      'x-accel-buffering': 'no',
      'x-request-id': opts.requestId,
    },
  });
}
