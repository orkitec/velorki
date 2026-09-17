// SPDX-License-Identifier: AGPL-3.0-only
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import ShareDetails from '@/app/(share)/s/[id]/ShareDetails';
import { loadShare } from '@/app/(share)/s/[id]/page';
import { SHARE_TTL_MS, ShareStore } from '@/share/store';
import { sampleGpx, withEnv } from './helpers';

// The share page as HTML: what a browser (and the app's "Open in Velorki"
// button) gets. Values and escaping are asserted on the real markup, as the
// Fastify page tests did.
describe('share page markup', () => {
  it('renders the name, stats, deep link and GPX link', () => {
    const store = new ShareStore(':memory:');
    const record = store.create({
      kind: 'route',
      name: 'Uetliberg loop',
      gpx: sampleGpx(5),
      summary: { distance_km: 42.4, ascent_m: 730, duration_s: 7200 },
    });
    const html = renderToStaticMarkup(<ShareDetails record={record} map={null} />);
    expect(html).toContain('Uetliberg loop');
    expect(html).toContain('42.4 km');
    expect(html).toContain('730 m');
    expect(html).toContain('2 h 00 min');
    expect(html).toContain(`velorki://share/${record.id}`);
    expect(html).toContain(`/s/${record.id}.gpx`);
    store.close();
  });

  it('escapes a hostile name', () => {
    const store = new ShareStore(':memory:');
    const record = store.create({
      kind: 'ride',
      name: '<script>alert(1)</script>',
      gpx: sampleGpx(3),
      summary: { distance_km: 1 },
    });
    const html = renderToStaticMarkup(<ShareDetails record={record} map={null} />);
    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).toContain('&lt;script&gt;');
    store.close();
  });
});

/**
 * The page itself is one `notFound()` branch around `loadShare`, so the lookup
 * is what the test drives. `null` is what makes the page answer 404 rather than
 * render the "no longer available" body with a 200 - the bug this guards.
 */
describe('share page lookup', () => {
  it('finds a live share and refuses unknown, malformed and expired ids', async () => {
    let now = Date.UTC(2026, 0, 1);
    const store = new ShareStore(':memory:', () => now);
    await withEnv(
      {},
      () => {
        const record = store.create({
          kind: 'route',
          name: 'Uetliberg loop',
          gpx: sampleGpx(3),
          summary: { distance_km: 42.4 },
        });

        expect(loadShare(record.id)?.id).toBe(record.id);

        // Well-formed but unknown, and never minted at all.
        expect(loadShare('ZZZZZZZZZZ')).toBeNull();
        expect(loadShare('short')).toBeNull();
        expect(loadShare('has-dash-x')).toBeNull();

        // Expired reads exactly like unknown.
        now += SHARE_TTL_MS + 1;
        expect(loadShare(record.id)).toBeNull();
      },
      { store },
    );
    store.close();
  });
});
