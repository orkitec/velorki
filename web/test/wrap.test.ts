// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { ApiError } from '@/server/errors';
import { parseWrapKeys, unwrapToken, wrapToken, wrapTokensIn } from '@/server/wrap';
import { TEST_WRAP_KEYS, WRAP_KEY_1, WRAP_KEY_2, testConfig } from './helpers';

const keys = parseWrapKeys(TEST_WRAP_KEYS);

describe('parseWrapKeys', () => {
  it('takes the first entry as current and keeps every entry for unwrapping', () => {
    expect(keys.current).toBe('k2');
    expect([...keys.keys.keys()]).toEqual(['k2', 'k1']);
    expect(parseWrapKeys(` ${WRAP_KEY_1} , `).current).toBe('k1');
  });

  it('refuses malformed entries without echoing key material', () => {
    const secret = Buffer.alloc(32, 9).toString('base64');
    for (const raw of ['', 'nokid', `bad kid:${secret}`, `k1:${secret},k1:${secret}`, 'k1:c2hvcnQ=']) {
      let message = '';
      try {
        parseWrapKeys(raw);
      } catch (err) {
        message = err instanceof Error ? err.message : String(err);
      }
      expect(message, raw).not.toBe('');
      expect(message, raw).not.toContain(secret);
    }
  });

  it('is fatal at configuration time', () => {
    expect(() => testConfig({ TOKEN_WRAP_KEYS: 'k1:short' })).toThrow(/TOKEN_WRAP_KEYS/);
    expect(testConfig({ TOKEN_WRAP_KEYS: '' }).TOKEN_WRAP_KEYS).toBeUndefined();
    expect(testConfig().TOKEN_WRAP_KEYS?.current).toBe('k2');
  });
});

describe('wrapToken / unwrapToken', () => {
  it('round-trips under the current key and is not stale', () => {
    const wrapped = wrapToken(keys, 'strava', 'access', 'a-strava-token');
    expect(wrapped).toMatch(/^v1\.k2\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
    expect(wrapped).not.toContain('a-strava-token');
    expect(unwrapToken(keys, 'strava', 'access', wrapped)).toEqual({
      token: 'a-strava-token',
      stale: false,
    });
  });

  it('uses a fresh nonce every time', () => {
    const a = wrapToken(keys, 'strava', 'access', 'same');
    const b = wrapToken(keys, 'strava', 'access', 'same');
    expect(a).not.toBe(b);
  });

  it('refuses a token wrapped for another service or kind', () => {
    const wrapped = wrapToken(keys, 'strava', 'access', 'tok');
    expect(() => unwrapToken(keys, 'rwgps', 'access', wrapped)).toThrow(ApiError);
    expect(() => unwrapToken(keys, 'strava', 'refresh', wrapped)).toThrow(ApiError);
  });

  it('still opens a token under an old key and says so', () => {
    const old = parseWrapKeys(WRAP_KEY_1);
    const wrapped = wrapToken(old, 'rwgps', 'access', 'rw');
    expect(wrapped.startsWith('v1.k1.')).toBe(true);
    expect(unwrapToken(keys, 'rwgps', 'access', wrapped)).toEqual({ token: 'rw', stale: true });
  });

  it('refuses an unknown kid, a tampered body and junk', () => {
    const wrapped = wrapToken(keys, 'strava', 'access', 'tok');
    const [, , nonce, body] = wrapped.split('.') as [string, string, string, string];
    const flipped = body.slice(0, -2) + (body.endsWith('AA') ? 'BB' : 'AA');
    for (const bad of [
      `v1.k9.${nonce}.${body}`,
      `v1.k2.${nonce}.${flipped}`,
      `v2.k2.${nonce}.${body}`,
      'v1.k2.short.short',
      '',
      'not a token',
      wrapped + '.extra',
    ]) {
      expect(() => unwrapToken(keys, 'strava', 'access', bad), bad).toThrow(ApiError);
    }
    let code = '';
    try {
      unwrapToken(parseWrapKeys(WRAP_KEY_2), 'strava', 'access', `v1.k1.${nonce}.${body}`);
    } catch (err) {
      code = err instanceof ApiError ? err.code : 'other';
    }
    expect(code).toBe('invalid_request');
  });
});

describe('wrapTokensIn', () => {
  it('wraps both tokens of a provider answer and leaves the rest alone', () => {
    const body = wrapTokensIn(
      { token_type: 'Bearer', access_token: 'a1', refresh_token: 'r1', athlete: { id: 7 } },
      keys,
      'strava',
    ) as Record<string, unknown>;
    expect(body['token_type']).toBe('Bearer');
    expect(body['athlete']).toEqual({ id: 7 });
    expect(unwrapToken(keys, 'strava', 'access', body['access_token'] as string).token).toBe('a1');
    expect(unwrapToken(keys, 'strava', 'refresh', body['refresh_token'] as string).token).toBe(
      'r1',
    );
  });

  it('passes anything that is not an object, or has no tokens, through', () => {
    expect(wrapTokensIn(null, keys, 'strava')).toBeNull();
    expect(wrapTokensIn([1], keys, 'strava')).toEqual([1]);
    expect(wrapTokensIn({ error: 'x', access_token: '' }, keys, 'rwgps')).toEqual({
      error: 'x',
      access_token: '',
    });
  });
});
