// SPDX-License-Identifier: AGPL-3.0-only
import { afterEach, describe, expect, it, vi } from 'vitest';
import { POST as plusWeb } from '@/app/(api)/plus/web/route';
import { POST as aiPlan } from '@/app/(api)/ai/plan/route';
import { freshIds, FRESH_FOR_MS } from '@/plus/devices';
import { mintPlusToken, plusSubject, verifyPlusToken } from '@/plus/token';
import { applyCors, corsMethods } from '@/server/cors';
import { bodyOf, errOf, jsonRequest, mockToolCallModel, revenueCatResponse, withEnv } from './helpers';

afterEach(() => {
  vi.unstubAllGlobals();
});

const SECRET = Buffer.alloc(32, 7).toString('base64');
const URL_PLUS = 'https://api.velorki.com/plus/web';
const DAY = 24 * 3_600_000;

const liveEnv = {
  REVENUECAT_MODE: 'live',
  REVENUECAT_SECRET_KEY: 'sk_test',
  PLUS_TOKEN_SECRET: SECRET,
  CLOUDKIT_API_TOKEN: 'ck-api-token',
};

interface Device {
  id: string;
  lastSeen: number;
  platform?: string;
}

interface Calls {
  drive: URL[];
  cloudkit: { url: URL; init: RequestInit }[];
  revenuecat: string[];
}

/**
 * Stubs Drive, CloudKit and RevenueCat by URL. `devices` are the records in
 * the rider's cloud; `entitled` the RevenueCat ids with an active Plus.
 */
function stubUpstream(opts: {
  devices: Device[];
  entitled?: string[];
  driveStatus?: number;
  cloudkit?: (url: URL, init: RequestInit) => Response;
}): Calls {
  const calls: Calls = { drive: [], cloudkit: [], revenuecat: [] };
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: string | URL, init: RequestInit = {}) => {
      const url = new URL(String(input));
      if (url.host === 'www.googleapis.com') {
        calls.drive.push(url);
        if (opts.driveStatus !== undefined) return new Response('{}', { status: opts.driveStatus });
        return Response.json({
          files: opts.devices.map((d, i) => ({
            name: `plus_device-${String(i)}`,
            appProperties: {
              kind: 'PlusDevice',
              modifiedAt: String(d.lastSeen),
              appUserId: d.id,
              platform: d.platform ?? 'android',
              lastSeen: String(d.lastSeen),
            },
          })),
        });
      }
      if (url.host === 'api.apple-cloudkit.com') {
        calls.cloudkit.push({ url, init });
        if (opts.cloudkit !== undefined) return opts.cloudkit(url, init);
        return Response.json({
          records: opts.devices.map((d, i) => ({
            recordName: `plus_device-${String(i)}`,
            recordType: 'PlusDevice',
            fields: {
              appUserId: { value: d.id, type: 'STRING' },
              platform: { value: d.platform ?? 'ios', type: 'STRING' },
              lastSeen: { value: d.lastSeen, type: 'INT64' },
            },
          })),
        });
      }
      if (url.host === 'api.revenuecat.com') {
        const id = decodeURIComponent(url.pathname.split('/').pop() ?? '');
        calls.revenuecat.push(id);
        return opts.entitled?.includes(id) === true
          ? revenueCatResponse('plus', null)
          : revenueCatResponse('plus', undefined);
      }
      throw new Error(`unexpected fetch ${url.href}`);
    }),
  );
  return calls;
}

function ask(service: string, token = 'cloud-token'): Promise<Response> {
  return plusWeb(jsonRequest(URL_PLUS, { service, token }));
}

interface Minted {
  token: string;
  expires_at: number;
  ck_web_auth_token?: string;
}

describe('POST /plus/web', () => {
  it('answers a Plus token for a Google account whose app has Plus', async () => {
    const now = Date.now();
    const calls = stubUpstream({
      devices: [
        { id: 'anon-free', lastSeen: now - DAY },
        { id: 'anon-plus', lastSeen: now - 2 * DAY },
      ],
      entitled: ['anon-plus'],
    });
    await withEnv(liveEnv, async () => {
      const res = await ask('google', 'ya29.token');
      expect(res.status).toBe(200);
      const body = await bodyOf<Minted>(res);
      expect(body.token.startsWith('vpt1.')).toBe(true);
      expect(body.expires_at).toBeGreaterThan(now / 1000 + 3_000);
      expect(body.expires_at).toBeLessThanOrEqual(now / 1000 + 3_601);
      // The id never reaches the browser, not even inside the token.
      expect(JSON.stringify(body)).not.toContain('anon-plus');
      const payload = Buffer.from(body.token.split('.')[1] ?? '', 'base64url').toString();
      expect(payload).not.toContain('anon-plus');
    });
    const drive = calls.drive[0];
    expect(drive?.searchParams.get('spaces')).toBe('appDataFolder');
    expect(drive?.searchParams.get('q')).toContain("name contains 'plus_'");
    expect(calls.revenuecat).toEqual(['anon-free', 'anon-plus']);
  });

  it('reads iCloud through CloudKit Web Services with the web auth token', async () => {
    const now = Date.now();
    const calls = stubUpstream({ devices: [{ id: 'anon-ios', lastSeen: now }], entitled: ['anon-ios'] });
    await withEnv(liveEnv, async () => {
      const res = await ask('icloud', 'a+b/c=');
      expect(res.status).toBe(200);
    });
    const call = calls.cloudkit[0];
    expect(call?.url.pathname).toBe(
      '/database/1/iCloud.com.orkitec.velorki/production/private/records/query',
    );
    expect(call?.url.searchParams.get('ckAPIToken')).toBe('ck-api-token');
    expect(call?.url.searchParams.get('ckWebAuthToken')).toBe('a+b/c=');
    expect(call?.url.search).toContain('ckWebAuthToken=a%2Bb%2Fc%3D');
    expect(new Headers(call?.init.headers).get('origin')).toBe('https://app.velorki.com');
    const sent = JSON.parse(call?.init.body as string) as {
      zoneID: { zoneName: string };
      query: { recordType: string };
    };
    expect(sent.zoneID.zoneName).toBe('Library');
    expect(sent.query.recordType).toBe('PlusDevice');
  });

  it('passes on the web auth token CloudKit hands out in exchange', async () => {
    const now = Date.now();
    stubUpstream({
      devices: [],
      entitled: ['anon-ios'],
      cloudkit: () =>
        Response.json({
          ckWebAuthToken: 'next-token',
          records: [
            {
              recordName: 'plus_x',
              recordType: 'PlusDevice',
              fields: {
                appUserId: { value: 'anon-ios' },
                platform: { value: 'ios' },
                lastSeen: { value: now },
              },
            },
          ],
        }),
    });
    await withEnv(liveEnv, async () => {
      const body = await bodyOf<Minted>(await ask('icloud'));
      expect(body.ck_web_auth_token).toBe('next-token');
    });
  });

  it('ignores devices not seen for 30 days', async () => {
    const now = Date.now();
    const calls = stubUpstream({
      devices: [{ id: 'anon-old', lastSeen: now - 31 * DAY }],
      entitled: ['anon-old'],
    });
    await withEnv(liveEnv, async () => {
      const res = await ask('google');
      expect(res.status).toBe(403);
      const err = (await errOf(res)) as { code: string; reason?: string };
      expect(err.code).toBe('not_entitled');
      expect(err.reason).toBe('no_devices');
    });
    expect(calls.revenuecat).toEqual([]);
  });

  it('refuses a cloud no app wrote to', async () => {
    stubUpstream({ devices: [] });
    await withEnv(liveEnv, async () => {
      const res = await ask('google');
      expect(res.status).toBe(403);
      expect(((await errOf(res)) as { reason?: string }).reason).toBe('no_devices');
    });
  });

  it('treats an iCloud account without the zone as no devices', async () => {
    stubUpstream({
      devices: [],
      cloudkit: () => Response.json({ serverErrorCode: 'ZONE_NOT_FOUND' }, { status: 404 }),
    });
    await withEnv(liveEnv, async () => {
      const res = await ask('icloud');
      expect(res.status).toBe(403);
      expect(((await errOf(res)) as { reason?: string }).reason).toBe('no_devices');
    });
  });

  it('refuses fresh devices without Plus', async () => {
    stubUpstream({ devices: [{ id: 'anon-free', lastSeen: Date.now() }], entitled: [] });
    await withEnv(liveEnv, async () => {
      const res = await ask('google');
      expect(res.status).toBe(403);
      expect(((await errOf(res)) as { reason?: string }).reason).toBe('not_subscribed');
    });
  });

  it('never trusts an id the client sends', async () => {
    const calls = stubUpstream({ devices: [], entitled: ['anon-stolen'] });
    await withEnv(liveEnv, async () => {
      const res = await plusWeb(
        jsonRequest(
          URL_PLUS,
          { service: 'google', token: 't', app_user_id: 'anon-stolen', ids: ['anon-stolen'] },
          { authorization: 'Bearer anon-stolen' },
        ),
      );
      expect(res.status).toBe(403);
    });
    expect(calls.revenuecat).toEqual([]);
  });

  it('says when the cloud refuses the sign-in', async () => {
    stubUpstream({ devices: [], driveStatus: 401 });
    await withEnv(liveEnv, async () => {
      const res = await ask('google');
      expect(res.status).toBe(401);
      expect(((await errOf(res)) as { reason?: string }).reason).toBe('cloud_auth');
    });
    stubUpstream({
      devices: [],
      cloudkit: () => Response.json({ serverErrorCode: 'AUTHENTICATION_REQUIRED' }, { status: 421 }),
    });
    await withEnv(liveEnv, async () => {
      const res = await ask('icloud');
      expect(res.status).toBe(401);
      expect(((await errOf(res)) as { reason?: string }).reason).toBe('cloud_auth');
    });
  });

  it('is 503 without a token secret, and iCloud without an API token', async () => {
    stubUpstream({ devices: [] });
    await withEnv({ ...liveEnv, PLUS_TOKEN_SECRET: '' }, async () => {
      expect((await ask('google')).status).toBe(503);
    });
    await withEnv({ ...liveEnv, CLOUDKIT_API_TOKEN: '' }, async () => {
      expect((await ask('icloud')).status).toBe(503);
    });
  });

  it('validates the body', async () => {
    await withEnv(liveEnv, async () => {
      expect((await ask('dropbox')).status).toBe(400);
      expect((await ask('google', '')).status).toBe(400);
    });
  });

  it('limits how often one cloud token asks', async () => {
    stubUpstream({ devices: [] });
    await withEnv(liveEnv, async () => {
      for (let i = 0; i < 10; i += 1) expect((await ask('google', 'same')).status).toBe(403);
      expect((await ask('google', 'same')).status).toBe(429);
      expect((await ask('google', 'other')).status).toBe(403);
    });
  });

  it('is a CORS route for the planner', () => {
    expect(corsMethods('/plus/web')).toEqual(['POST']);
    const res = new Response(null);
    applyCors(res, ['https://app.velorki.com'], '/plus/web', 'https://app.velorki.com');
    expect(res.headers.get('access-control-allow-origin')).toBe('https://app.velorki.com');
  });
});

describe('Plus tokens', () => {
  it('verify while fresh and unforged', () => {
    const now = Date.now();
    const { token } = mintPlusToken(SECRET, 'subj', now);
    expect(verifyPlusToken(SECRET, token, now)).toBe('subj');
    expect(verifyPlusToken(SECRET, token, now + 3_601_000)).toBeNull();
    expect(verifyPlusToken(Buffer.alloc(32, 8).toString('base64'), token, now)).toBeNull();
    const [prefix, , mac] = token.split('.');
    const forged = Buffer.from(JSON.stringify({ s: 'subj', e: now / 1000 + 99_999 })).toString(
      'base64url',
    );
    expect(verifyPlusToken(SECRET, `${prefix ?? ''}.${forged}.${mac ?? ''}`, now)).toBeNull();
    expect(token.length).toBeLessThanOrEqual(256);
  });

  it('keep the RevenueCat id out of the subject', () => {
    expect(plusSubject(SECRET, 'anon-1')).not.toContain('anon');
    expect(plusSubject(SECRET, 'anon-1')).toBe(plusSubject(SECRET, 'anon-1'));
  });

  it('fresh ids are the newest first, each once', () => {
    const now = Date.now();
    expect(
      freshIds(
        [
          { appUserId: 'a', platform: 'ios', lastSeenMs: now - 2 * DAY },
          { appUserId: 'b', platform: 'ios', lastSeenMs: now },
          { appUserId: 'a', platform: 'ios', lastSeenMs: now - DAY },
          { appUserId: 'c', platform: 'ios', lastSeenMs: now - FRESH_FOR_MS - 1 },
        ],
        now,
      ),
    ).toEqual(['b', 'a']);
  });
});

describe('a Plus token on a Plus route', () => {
  const llm = {
    LLM_BASE_URL: 'http://llm.internal/v1',
    LLM_MODEL: 'some-model',
  };
  const planBody = {
    step: 'plan',
    locale: 'en',
    units: 'metric',
    prompt: 'A 40 km loop.',
    context: { start: { lat: 47.38, lon: 8.54 }, today: '2026-10-19' },
  };
  const route = {
    distance_km: 40,
    loop: true,
    start: { use_current: true },
    via: [],
    surface: 'mixed',
    hills: 'avoid',
    traffic_tolerance: 'low',
    stops: [],
    profile_hint: 'trekking',
    notes: 'A loop.',
    confidence: 0.8,
  };

  function plan(bearer: string): Promise<Response> {
    return aiPlan(
      jsonRequest('https://api.velorki.com/ai/plan', planBody, {
        authorization: `Bearer ${bearer}`,
        'x-ai-consent': '1',
      }),
    );
  }

  it('is accepted in place of the app id, with no RevenueCat call', async () => {
    const fetchMock = vi.fn(() => {
      throw new Error('RevenueCat must not be asked');
    });
    vi.stubGlobal('fetch', fetchMock);
    const { token } = mintPlusToken(SECRET, 'subj');
    await withEnv(
      { ...liveEnv, ...llm },
      async () => {
        const res = await plan(token);
        expect(res.status).toBe(200);
        await res.text();
      },
      { getModel: () => mockToolCallModel(route) },
    );
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('is refused when expired or forged', async () => {
    vi.stubGlobal('fetch', vi.fn());
    const expired = mintPlusToken(SECRET, 'subj', Date.now() - 2 * 3_600_000).token;
    const forged = mintPlusToken(Buffer.alloc(32, 9).toString('base64'), 'subj').token;
    await withEnv(
      { ...liveEnv, ...llm },
      async () => {
        for (const token of [expired, forged, 'vpt1.garbage']) {
          const res = await plan(token);
          expect(res.status, token).toBe(401);
          expect((await errOf(res)).code).toBe('not_entitled');
        }
      },
      { getModel: () => mockToolCallModel(route) },
    );
  });

  it('keeps the app path: a RevenueCat id with Plus still works', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => revenueCatResponse('plus', null)));
    await withEnv(
      { ...liveEnv, ...llm },
      async () => {
        const res = await plan('anon-app');
        expect(res.status).toBe(200);
        await res.text();
      },
      { getModel: () => mockToolCallModel(route) },
    );
  });
});
