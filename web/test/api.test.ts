// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { pino, type Logger } from 'pino';
import { logFailure, withApi } from '@/server/api';
import { ApiError } from '@/server/errors';
import { withEnv } from './helpers';

/**
 * Capture what pino actually writes, as raw text: the bug this guards against
 * only exists after serialisation, and parsing the line would hide it.
 */
function capturingLogger(): { logger: Logger; lines: string[] } {
  const lines: string[] = [];
  const logger = pino(
    { level: 'debug', base: {} },
    { write: (line: string) => lines.push(line) },
  );
  return { logger, lines };
}

describe('logFailure', () => {
  it('reports the failure detail without shadowing pino’s own msg', () => {
    const { logger, lines } = capturingLogger();

    logFailure(logger, new ApiError('unavailable', 'Strava is not configured.'), undefined);
    logFailure(logger, new ApiError('invalid_request', 'redirect_uri is not allowed.'), undefined);

    // A `msg` field in the merging object is emitted a second time and every
    // JSON parser keeps only the last one, so the detail would be lost.
    for (const line of lines) {
      expect(line.match(/"msg":/g)).toHaveLength(1);
    }

    expect(JSON.parse(lines[0]!)).toMatchObject({
      msg: 'request unavailable',
      level: 40,
      code: 'unavailable',
      reason: 'Strava is not configured.',
    });
    expect(JSON.parse(lines[1]!)).toMatchObject({
      msg: 'request rejected',
      level: 20,
      code: 'invalid_request',
      reason: 'redirect_uri is not allowed.',
    });
  });
});

describe('withApi', () => {
  it('stamps the echoed request id and no-store on a thrown ApiError', async () => {
    await withEnv({}, async () => {
      const handler = withApi(async () => {
        throw new ApiError('invalid_request', 'nope');
      });
      const res = await handler(
        new Request('https://api.velorki.com/share', {
          method: 'POST',
          headers: { 'x-request-id': 'trace-1' },
        }),
      );
      expect(res.status).toBe(400);
      expect(res.headers.get('x-request-id')).toBe('trace-1');
      expect(res.headers.get('cache-control')).toBe('no-store');
      expect(await res.json()).toEqual({
        error: { code: 'invalid_request', message: 'nope' },
      });
    });
  });
});
