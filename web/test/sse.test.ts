// SPDX-License-Identifier: AGPL-3.0-only
import { afterEach, describe, expect, it, vi } from 'vitest';
import { PING_INTERVAL_MS, sseResponse } from '@/server/sse';

afterEach(() => {
  vi.useRealTimers();
});

/** Read the stream chunk by chunk so a ping can be observed as it arrives. */
function reader(res: Response): { next: () => Promise<string>; cancel: () => Promise<void> } {
  const r = res.body!.getReader();
  const decoder = new TextDecoder();
  return {
    async next() {
      const { value, done } = await r.read();
      return done || value === undefined ? '' : decoder.decode(value);
    },
    async cancel() {
      await r.cancel();
    },
  };
}

describe('sseResponse', () => {
  it('sets the headers the relay sent', async () => {
    const res = sseResponse({
      requestId: 'req-1',
      run: async (sse) => {
        sse.send('done', { ok: true });
      },
    });

    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toBe('text/event-stream; charset=utf-8');
    expect(res.headers.get('cache-control')).toBe('no-cache, no-transform');
    expect(res.headers.get('connection')).toBe('keep-alive');
    expect(res.headers.get('x-accel-buffering')).toBe('no');
    expect(res.headers.get('x-request-id')).toBe('req-1');
    await res.text();
  });

  it('opens with the : open preamble and frames events', async () => {
    const res = sseResponse({
      requestId: 'req-2',
      run: async (sse) => {
        sse.send('text', { delta: 'hi' });
        sse.send('done', { usage: { in: 1, out: 2 } });
      },
    });
    expect(await res.text()).toBe(
      ': open\n\n' +
        'event: text\ndata: {"delta":"hi"}\n\n' +
        'event: done\ndata: {"usage":{"in":1,"out":2}}\n\n',
    );
  });

  it('serialises a missing payload as an empty object', async () => {
    const res = sseResponse({
      requestId: 'req-3',
      run: async (sse) => {
        sse.send('ping-ish', undefined);
      },
    });
    expect(await res.text()).toBe(': open\n\nevent: ping-ish\ndata: {}\n\n');
  });

  it('writes a : ping comment every 20 s while a run stalls', async () => {
    vi.useFakeTimers();
    let release: (() => void) | undefined;
    const stalled = new Promise<void>((resolve) => {
      release = resolve;
    });

    const res = sseResponse({
      requestId: 'req-4',
      run: async (sse) => {
        await stalled;
        sse.send('done', {});
      },
    });

    const r = reader(res);
    expect(await r.next()).toBe(': open\n\n');

    await vi.advanceTimersByTimeAsync(PING_INTERVAL_MS);
    expect(await r.next()).toBe(': ping\n\n');
    await vi.advanceTimersByTimeAsync(PING_INTERVAL_MS);
    expect(await r.next()).toBe(': ping\n\n');

    release?.();
    expect(await r.next()).toBe('event: done\ndata: {}\n\n');
    expect(await r.next()).toBe('');
  });

  it('aborts the run when the request signal fires', async () => {
    const controller = new AbortController();
    let aborted = false;

    const res = sseResponse({
      requestId: 'req-5',
      signal: controller.signal,
      run: async (sse, signal) => {
        await new Promise<void>((resolve) => {
          signal.addEventListener('abort', () => {
            aborted = true;
            resolve();
          });
        });
        sse.send('error', { error: { code: 'upstream_error', message: 'aborted' } });
      },
    });

    const r = reader(res);
    expect(await r.next()).toBe(': open\n\n');
    controller.abort();
    expect(await r.next()).toContain('event: error');
    expect(aborted).toBe(true);
  });

  it('aborts the run when the consumer cancels the stream', async () => {
    let aborted = false;
    const res = sseResponse({
      requestId: 'req-6',
      run: async (_sse, signal) => {
        await new Promise<void>((resolve) => {
          signal.addEventListener('abort', () => {
            aborted = true;
            resolve();
          });
        });
      },
    });

    const r = reader(res);
    expect(await r.next()).toBe(': open\n\n');
    await r.cancel();
    // The cancel() callback aborts synchronously; give the listener a tick.
    await Promise.resolve();
    expect(aborted).toBe(true);
  });

  it('starts already aborted when the request was cancelled before the stream', async () => {
    let seen = false;
    const res = sseResponse({
      requestId: 'req-7',
      signal: AbortSignal.abort(),
      run: async (_sse, signal) => {
        seen = signal.aborted;
      },
    });
    await res.text();
    expect(seen).toBe(true);
  });
});
