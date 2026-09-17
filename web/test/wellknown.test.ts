// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { GET } from '@/app/(site)/well-known/[file]/route';
import { errOf, withEnv } from './helpers';

function call(file: string): Promise<Response> {
  return GET(new Request(`https://velorki.com/.well-known/${file}`), {
    params: Promise.resolve({ file }),
  });
}

describe('/.well-known association files', () => {
  it('serves apple-app-site-association when the team id is configured', async () => {
    await withEnv({ APPLE_TEAM_ID: 'ABCDE12345' }, async () => {
      const res = await call('apple-app-site-association');
      expect(res.status).toBe(200);
      expect(res.headers.get('content-type')).toBe('application/json');
      expect(await res.json()).toEqual({
        applinks: {
          details: [{ appIDs: ['ABCDE12345.com.orkitec.velorki'], paths: ['/s/*'] }],
        },
      });
    });
  });

  it('serves assetlinks.json with every configured fingerprint', async () => {
    await withEnv({ ANDROID_CERT_SHA256: 'AA:BB , CC:DD' }, async () => {
      const res = await call('assetlinks.json');
      expect(res.status).toBe(200);
      expect(await res.json()).toEqual([
        {
          relation: ['delegate_permission/common.handle_all_urls'],
          target: {
            namespace: 'android_app',
            package_name: 'com.orkitec.velorki',
            sha256_cert_fingerprints: ['AA:BB', 'CC:DD'],
          },
        },
      ]);
    });
  });

  it('404s each file when its key is unset, so nothing is advertised', async () => {
    await withEnv({}, async () => {
      for (const file of ['apple-app-site-association', 'assetlinks.json']) {
        const res = await call(file);
        expect(res.status, file).toBe(404);
        expect((await errOf(res)).code).toBe('not_found');
      }
    });
  });

  it('404s an unset key even when the other one is configured', async () => {
    await withEnv({ APPLE_TEAM_ID: 'ABCDE12345' }, async () => {
      expect((await call('assetlinks.json')).status).toBe(404);
      expect((await call('apple-app-site-association')).status).toBe(200);
    });
  });

  it('404s anything else under /.well-known', async () => {
    await withEnv({ APPLE_TEAM_ID: 'ABCDE12345', ANDROID_CERT_SHA256: 'AA:BB' }, async () => {
      for (const file of ['security.txt', 'assetlinks', 'apple-app-site-association.json']) {
        const res = await call(file);
        expect(res.status, file).toBe(404);
        expect((await errOf(res)).code).toBe('not_found');
      }
    });
  });
});
