// SPDX-License-Identifier: AGPL-3.0-only
import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { fingerprint } from '@/server/fingerprint';

describe('fingerprint', () => {
  it('is absent for an unset or empty secret', () => {
    expect(fingerprint(undefined)).toBeNull();
    expect(fingerprint('')).toBeNull();
  });

  it('matches what `printf %s "$KEY" | sha256sum | cut -c1-8` prints', () => {
    const key = 'sk-or-v1-0123456789abcdef';
    const expected = createHash('sha256').update(key).digest('hex').slice(0, 8);
    expect(fingerprint(key)).toBe(`sha256:${expected}`);
  });

  it('tells two keys apart without containing either', () => {
    const a = fingerprint('sk-or-v1-aaaaaaaaaaaaaaaa');
    const b = fingerprint('sk-or-v1-bbbbbbbbbbbbbbbb');
    expect(a).not.toBe(b);
    expect(a).not.toContain('aaaa');
  });
});
