// SPDX-License-Identifier: AGPL-3.0-only
import { afterEach, describe, expect, it, vi } from 'vitest';
import { POST as stravaToken } from '@/app/(api)/oauth/strava/token/route';
import { AUTH, errOf, jsonRequest, withEnv } from './helpers';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('HTTP rate limiting', () => {
  it('returns 429 with retry_after_s and a Retry-After header', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(JSON.stringify({ access_token: 'a' }), { status: 200 })),
    );

    await withEnv(
      {
        STRAVA_CLIENT_ID: '1',
        STRAVA_CLIENT_SECRET: 's',
        OAUTH_REDIRECT_ALLOWLIST: 'velorki://oauth/strava',
      },
      async () => {
        const call = () =>
          stravaToken(
            jsonRequest(
              'https://api.velorki.com/oauth/strava/token',
              { code: 'c', redirect_uri: 'velorki://oauth/strava' },
              AUTH,
            ),
          );

        // The per-minute limit for the strava token route is 10.
        for (let i = 0; i < 10; i += 1) {
          expect((await call()).status, `call ${String(i)}`).toBe(200);
        }

        const limited = await call();
        expect(limited.status).toBe(429);
        const body = await errOf(limited);
        expect(body.code).toBe('rate_limited');
        expect(body.retry_after_s).toBeGreaterThan(0);
        expect(limited.headers.get('retry-after')).toBe(String(body.retry_after_s));
      },
    );
  });

  it('keys the per-IP limits by CLIENT_IP_HEADER when it is configured', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(JSON.stringify({ access_token: 'a' }), { status: 200 })),
    );

    await withEnv(
      {
        STRAVA_CLIENT_ID: '1',
        STRAVA_CLIENT_SECRET: 's',
        OAUTH_REDIRECT_ALLOWLIST: 'velorki://oauth/strava',
        // The header is only read behind a trusted proxy.
        TRUST_PROXY: '1',
        CLIENT_IP_HEADER: 'cf-connecting-ip',
      },
      async () => {
        const call = (ip: string) =>
          stravaToken(
            jsonRequest(
              'https://api.velorki.com/oauth/strava/token',
              { code: 'c', redirect_uri: 'velorki://oauth/strava' },
              { ...AUTH, 'cf-connecting-ip': ip },
            ),
          );

        for (let i = 0; i < 10; i += 1) expect((await call('9.9.9.9')).status).toBe(200);
        expect((await call('9.9.9.9')).status).toBe(429);
        // A different client IP has its own window.
        expect((await call('8.8.8.8')).status).toBe(200);
      },
    );
  });
});

describe('clientIp', () => {
  it('falls back to x-forwarded-for only behind a trusted proxy', async () => {
    const { clientIp } = await import('@/config');
    const { testConfig } = await import('./helpers');
    const headers = new Headers({ 'x-forwarded-for': '203.0.113.7, 10.0.0.1' });

    expect(clientIp(testConfig({}), headers)).toBe('unknown');
    expect(clientIp(testConfig({ TRUST_PROXY: '1' }), headers)).toBe('203.0.113.7');
    expect(
      clientIp(
        testConfig({ TRUST_PROXY: '1', CLIENT_IP_HEADER: 'cf-connecting-ip' }),
        new Headers({ 'cf-connecting-ip': '198.51.100.4', 'x-forwarded-for': '1.1.1.1' }),
      ),
    ).toBe('198.51.100.4');
    // Without a trusted proxy the header is just something a client sent.
    expect(
      clientIp(
        testConfig({ CLIENT_IP_HEADER: 'cf-connecting-ip' }),
        new Headers({ 'cf-connecting-ip': '198.51.100.4', 'x-forwarded-for': '1.1.1.1' }),
      ),
    ).toBe('unknown');
  });
});
