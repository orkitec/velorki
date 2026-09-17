// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it, vi } from 'vitest';
import { NextRequest, NextResponse } from 'next/server';
import {
  getRedirectUrl,
  getRewrittenUrl,
  isRewrite,
  unstable_doesMiddlewareMatch,
} from 'next/experimental/testing/server';
import proxy, { config as proxyConfig } from '@/proxy';
import { SHARE_TTL_MS, ShareStore } from '@/share/store';
import { errOf, sampleGpx, withEnv } from './helpers';

/**
 * next-intl's middleware is published as ESM whose `next/server` import only
 * resolves inside a bundler, so it cannot be loaded here - which is why
 * `proxy.ts` imports it lazily in the first place. The locale branch is
 * exercised against a stand-in that answers the way next-intl does, `Vary`
 * header included, so what is asserted is the proxy's own contribution.
 */
vi.mock('next-intl/middleware', () => ({
  default: () => (): NextResponse => {
    const response = NextResponse.next();
    response.headers.set('vary', 'accept-language');
    return response;
  },
}));

/**
 * Next 16.3.5 still names the matcher helper `unstable_doesMiddlewareMatch`;
 * `proxy.ts` is the renamed middleware and uses the same `config.matcher`
 * shape, so the helper applies unchanged.
 */
function matches(url: string): boolean {
  return unstable_doesMiddlewareMatch({ config: proxyConfig, url });
}

function request(
  url: string,
  init: { method?: string; headers?: Record<string, string> } = {},
): NextRequest {
  const { host } = new URL(url);
  return new NextRequest(url, {
    method: init.method ?? 'GET',
    headers: { host, ...init.headers },
  });
}

const API = 'https://api.velorki.com';
const SITE = 'https://velorki.com';

/** A store holding exactly one live share, plus that share's id. */
function storeWithShare(): { store: ShareStore; id: string } {
  const store = new ShareStore(':memory:');
  const { id } = store.create({
    kind: 'route',
    name: 'Uetliberg loop',
    gpx: sampleGpx(3),
    summary: { distance_km: 42.4 },
  });
  return { store, id };
}

describe('config.matcher', () => {
  it('skips Next internals and static files but keeps .gpx', () => {
    expect(matches('/')).toBe(true);
    expect(matches('/health')).toBe(true);
    expect(matches('/de/docs/getting-started')).toBe(true);
    expect(matches('/s/AbCdEf0123')).toBe(true);
    expect(matches('/s/AbCdEf0123.gpx')).toBe(true);

    expect(matches('/_next/static/chunks/main.js')).toBe(false);
    expect(matches('/_next/image')).toBe(false);
    expect(matches('/favicon.ico')).toBe(false);
    expect(matches('/screenshots/dark/library.png')).toBe(false);
    expect(matches('/.well-known/assetlinks.json')).toBe(false);
  });
});

describe('host gate', () => {
  it('404s a Host that is neither the api nor the site', async () => {
    await withEnv({}, async () => {
      const res = await proxy(request(`${API}/health`, { headers: { host: 'evil.example.com' } }));
      expect(res.status).toBe(404);
      expect(res.headers.get('cache-control')).toBe('no-store');
      expect((await errOf(res)).code).toBe('not_found');
    });
  });

  it('lets an api route through without touching its cache policy', async () => {
    await withEnv({}, async () => {
      const res = await proxy(request(`${API}/health`));
      expect(res.status).toBe(200);
      expect(isRewrite(res)).toBe(false);
      // The proxy must not stamp one here: it would overwrite the handler's,
      // and `POST /ai/plan` needs `no-cache, no-transform` to survive.
      // `withApi` is what marks a handler answer `no-store`.
      expect(res.headers.get('cache-control')).toBeNull();
    });
  });

  it('answers the Fastify JSON 404 for an unknown method or path', async () => {
    await withEnv({}, async () => {
      const cases: [string, string, string][] = [
        ['GET', `${API}/`, 'No route for GET /.'],
        ['GET', `${API}/nope`, 'No route for GET /nope.'],
        ['GET', `${API}/share`, 'No route for GET /share.'],
        ['POST', `${API}/health`, 'No route for POST /health.'],
        ['GET', `${API}/nope?a=1&b=2`, 'No route for GET /nope?a=1&b=2.'],
      ];
      for (const [method, url, message] of cases) {
        const res = await proxy(request(url, { method }));
        expect(res.status, url).toBe(404);
        const body = await errOf(res);
        expect(body.code).toBe('not_found');
        expect(body.message).toBe(message);
      }
    });
  });

  it('accepts every documented api route', async () => {
    await withEnv({}, async () => {
      const routes: [string, string][] = [
        ['GET', '/health'],
        ['HEAD', '/health'],
        ['POST', '/oauth/strava/token'],
        ['POST', '/oauth/strava/refresh'],
        ['POST', '/oauth/rwgps/token'],
        ['POST', '/oauth/rwgps/refresh'],
        ['POST', '/ai/plan'],
        ['POST', '/share'],
      ];
      for (const [method, path] of routes) {
        const res = await proxy(request(`${API}${path}`, { method }));
        expect(res.status, `${method} ${path}`).toBe(200);
      }
    });
  });

  it('treats a loopback Host as the api role so the health probe works', async () => {
    await withEnv({}, async () => {
      for (const host of ['localhost:8080', '127.0.0.1:8080', '[::1]:8080']) {
        const res = await proxy(request(`${API}/health`, { headers: { host } }));
        expect(res.status, host).toBe(200);
        expect(res.headers.get('cache-control'), host).toBeNull();
      }

      const root = await proxy(request(`${API}/`, { headers: { host: 'localhost:8080' } }));
      expect(root.status).toBe(404);
      expect((await errOf(root)).message).toBe('No route for GET /.');
    });
  });

  it('redirects old api-host share links to the site host', async () => {
    await withEnv({}, async () => {
      const res = await proxy(request(`${API}/s/AbCdEf0123?utm=x`));
      expect(res.status).toBe(308);
      expect(getRedirectUrl(res)).toBe('https://velorki.com/s/AbCdEf0123?utm=x');
      // A response the proxy produces itself does carry the policy.
      expect(res.headers.get('cache-control')).toBe('no-store');
    });
  });
});

describe('DEV_HOSTS', () => {
  it('reaches the api role through the prefix, the header and api.localhost', async () => {
    await withEnv({ DEV_HOSTS: '1' }, async () => {
      const prefixed = await proxy(request('http://localhost:3000/__api/health'));
      expect(prefixed.status).toBe(200);
      expect(isRewrite(prefixed)).toBe(true);
      expect(getRewrittenUrl(prefixed)).toBe('http://localhost:3000/health');
      expect(prefixed.headers.get('cache-control')).toBeNull();

      const header = await proxy(
        request('http://localhost:3000/health', { headers: { 'x-velorki-host': 'api' } }),
      );
      expect(header.status).toBe(200);
      expect(header.headers.get('cache-control')).toBeNull();

      const subdomain = await proxy(request('http://api.localhost:3000/health'));
      expect(subdomain.status).toBe(200);
      expect(subdomain.headers.get('cache-control')).toBeNull();
    });
  });

  it('serves the site role on plain localhost', async () => {
    const { store, id } = storeWithShare();
    await withEnv(
      { DEV_HOSTS: '1' },
      async () => {
        const res = await proxy(request(`http://localhost:3000/s/${id}`));
        expect(res.status).toBe(200);
        expect(res.headers.get('cache-control')).toBe('public, max-age=300');
      },
      { store },
    );
    store.close();
  });

  it('still 404s an unknown host in development', async () => {
    await withEnv({ DEV_HOSTS: '1' }, async () => {
      const res = await proxy(request('http://elsewhere.test/'));
      expect(res.status).toBe(404);
    });
  });
});

describe('share paths on the site host', () => {
  it('lets a live id through and caches the page for 300 s', async () => {
    const { store, id } = storeWithShare();
    await withEnv(
      {},
      async () => {
        const res = await proxy(request(`${SITE}/s/${id}`));
        expect(res.status).toBe(200);
        expect(isRewrite(res)).toBe(false);
        expect(res.headers.get('cache-control')).toBe('public, max-age=300');
      },
      { store },
    );
    store.close();
  });

  /**
   * The status of an expired link has to be settled before the page renders:
   * under `cacheComponents` the page streams a shell first, so its own
   * `notFound()` could only ever produce a soft 404.
   */
  it('rewrites a well-formed but unknown id to the not-found route', async () => {
    const { store, id } = storeWithShare();
    await withEnv(
      {},
      async () => {
        const res = await proxy(request(`${SITE}/s/ZZZZZZZZZZ`));
        expect(isRewrite(res)).toBe(true);
        expect(getRewrittenUrl(res)).toBe('https://velorki.com/s/gone');
        expect(res.headers.get('cache-control')).toBe('no-store');

        // And the live one is still not rewritten.
        expect(isRewrite(await proxy(request(`${SITE}/s/${id}`)))).toBe(false);
      },
      { store },
    );
    store.close();
  });

  it('sends an expired id to the not-found route too', async () => {
    let now = Date.UTC(2026, 0, 1);
    const store = new ShareStore(':memory:', () => now);
    const { id } = store.create({
      kind: 'ride',
      name: 'Old ride',
      gpx: sampleGpx(3),
      summary: { distance_km: 3 },
    });
    await withEnv(
      {},
      async () => {
        expect(isRewrite(await proxy(request(`${SITE}/s/${id}`)))).toBe(false);
        now += SHARE_TTL_MS + 1;
        const res = await proxy(request(`${SITE}/s/${id}`));
        expect(getRewrittenUrl(res)).toBe('https://velorki.com/s/gone');
      },
      { store },
    );
    store.close();
  });

  it('rewrites .gpx to the gpx route without consulting the store', async () => {
    await withEnv({}, async () => {
      // The gpx route answers its own 404, so an unknown id still gets here.
      const res = await proxy(request(`${SITE}/s/AbCdEf0123.gpx`));
      expect(isRewrite(res)).toBe(true);
      expect(getRewrittenUrl(res)).toBe('https://velorki.com/s/AbCdEf0123/gpx');
    });
  });

  it('404s a malformed id before it reaches the page or the database', async () => {
    await withEnv({}, async () => {
      for (const path of [
        '/s/short',
        '/s/way-too-long-id',
        '/s/bad!chars',
        '/s/nope.gpx',
        '/s/',
        '/s/AbCdEf012.gpx',
      ]) {
        const res = await proxy(request(`${SITE}${path}`));
        expect(res.status, path).toBe(404);
        expect((await errOf(res)).message).toBe('No such share.');
      }
    });
  });

  it('passes /.well-known through untouched', async () => {
    await withEnv({}, async () => {
      const res = await proxy(request(`${SITE}/.well-known/apple-app-site-association`));
      expect(res.status).toBe(200);
      expect(isRewrite(res)).toBe(false);
    });
  });
});

/**
 * robots.txt and friends carry a file extension, which the main matcher
 * excludes. They are routes of ours, so they are named explicitly: without
 * that they would skip the host gate and answer 200 on the api host.
 */
const SITE_FILES = ['/robots.txt', '/sitemap.xml', '/llms.txt', '/llms-full.txt', '/manifest.webmanifest'];

describe('generated site files', () => {
  it('runs them through the proxy', () => {
    for (const path of SITE_FILES) expect(matches(path), path).toBe(true);
  });

  it('serves them on the site host without locale negotiation', async () => {
    await withEnv({}, async () => {
      for (const path of SITE_FILES) {
        const res = await proxy(
          request(`${SITE}${path}`, { headers: { 'accept-language': 'de-DE,de;q=0.9' } }),
        );
        expect(res.status, path).toBe(200);
        expect(isRewrite(res), path).toBe(false);
        expect(res.headers.get('location'), path).toBeNull();
        expect(res.headers.get('x-request-id'), path).toBeTruthy();
      }
    });
  });

  it('404s them on the api host like any other unknown route', async () => {
    await withEnv({}, async () => {
      for (const path of SITE_FILES) {
        const res = await proxy(request(`${API}${path}`));
        expect(res.status, path).toBe(404);
        const body = await errOf(res);
        expect(body.code).toBe('not_found');
        expect(body.message).toBe(`No route for GET ${path}.`);
      }
    });
  });
});

describe('locale negotiation', () => {
  /** `Vary` as a lower-cased set, so order and casing do not matter. */
  function vary(res: Response): Set<string> {
    const raw = res.headers.get('vary');
    if (raw === null) return new Set();
    return new Set(raw.split(',').map((v) => v.trim().toLowerCase()).filter((v) => v !== ''));
  }

  it('varies an HTML page by Accept-Language and Cookie', async () => {
    await withEnv({}, async () => {
      for (const path of ['/', '/download', '/de/docs/getting-started']) {
        const res = await proxy(
          request(`${SITE}${path}`, { headers: { 'accept-language': 'de-DE,de;q=0.9' } }),
        );
        expect(vary(res), path).toContain('accept-language');
        expect(vary(res), path).toContain('cookie');
      }
    });
  });

  it('keeps a Vary entry next-intl has already set', async () => {
    await withEnv({}, async () => {
      const res = await proxy(request(`${SITE}/`, { headers: { cookie: 'NEXT_LOCALE=de' } }));
      const entries = [...vary(res)];
      // No duplicates, whatever next-intl contributed.
      expect(entries.length).toBe(new Set(entries).size);
      expect(entries).toContain('accept-language');
    });
  });

  it('leaves the generated files and the share page unvaried', async () => {
    await withEnv({}, async () => {
      for (const path of [...SITE_FILES, '/s/AbCdEf0123', '/.well-known/assetlinks.json']) {
        const res = await proxy(
          request(`${SITE}${path}`, { headers: { 'accept-language': 'de-DE,de;q=0.9' } }),
        );
        expect(res.headers.get('vary'), path).toBeNull();
      }
    });
  });
});

describe('request id', () => {
  it('echoes a sane id and mints one otherwise, on every answer', async () => {
    await withEnv({}, async () => {
      const echoed = await proxy(request(`${SITE}/s/AbCdEf0123`, { headers: { 'x-request-id': 'trace-1' } }));
      expect(echoed.headers.get('x-request-id')).toBe('trace-1');

      const minted = await proxy(request(`${SITE}/s/AbCdEf0123`, { headers: { 'x-request-id': 'bad id' } }));
      expect(minted.headers.get('x-request-id')).toMatch(/^[0-9a-f-]{36}$/);

      const on404 = await proxy(request(`${API}/nope`, { headers: { 'x-request-id': 'trace-2' } }));
      expect(on404.headers.get('x-request-id')).toBe('trace-2');

      const onRedirect = await proxy(request(`${API}/s/AbCdEf0123`, { headers: { 'x-request-id': 'trace-3' } }));
      expect(onRedirect.headers.get('x-request-id')).toBe('trace-3');
    });
  });

  it('forwards the settled id to the handler', async () => {
    await withEnv({}, async () => {
      const res = await proxy(request(`${API}/health`, { headers: { 'x-request-id': 'trace-4' } }));
      expect(res.headers.get('x-middleware-override-headers')).toContain('x-request-id');
      expect(res.headers.get('x-middleware-request-x-request-id')).toBe('trace-4');
    });
  });
});
