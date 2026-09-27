// SPDX-License-Identifier: AGPL-3.0-only
import { afterEach, describe, expect, it } from 'vitest';
import { buildMeta } from '@/build-meta';

const saved = { release: process.env.VELORKI_RELEASE, commit: process.env.VELORKI_COMMIT };

function set(release?: string, commit?: string) {
  if (release === undefined) delete process.env.VELORKI_RELEASE;
  else process.env.VELORKI_RELEASE = release;
  if (commit === undefined) delete process.env.VELORKI_COMMIT;
  else process.env.VELORKI_COMMIT = commit;
}

afterEach(() => set(saved.release, saved.commit));

const SHA = '3d673110f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0';

describe('buildMeta', () => {
  it('is all null on a build that was never deployed', () => {
    set(undefined, undefined);
    expect(buildMeta()).toEqual({ release: null, commit: null, commitShort: null, commitUrl: null });
  });

  it("reads the release number out of Orkify's deployment id", () => {
    // What @orkify/cli's DeployExecutor passes into the build:
    // `v<version>-<artifactId.slice(0, 8)>`.
    set('v2-2e703f75', undefined);
    expect(buildMeta().release).toBe('v2');
    set('v17-abcdef12', undefined);
    expect(buildMeta().release).toBe('v17');
  });

  it('ignores a deployment id in any other shape', () => {
    // A hand-set NEXT_DEPLOYMENT_ID is legal Next configuration, and anything
    // that is not Orkify's release naming is not a release number.
    for (const id of ['', 'build-7', 'local-3', 'v-1', '2e703f75']) {
      set(id, undefined);
      expect(buildMeta().release, id).toBeNull();
    }
  });

  it('accepts a full commit sha and abbreviates it to seven', () => {
    set(undefined, SHA);
    expect(buildMeta()).toEqual({
      release: null,
      commit: SHA,
      commitShort: '3d67311',
      commitUrl: `https://github.com/orkitec/velorki/commit/${SHA}`,
    });
  });

  it('normalises whitespace and case around the sha', () => {
    set(undefined, `  ${SHA.toUpperCase()}\n`);
    expect(buildMeta().commit).toBe(SHA);
  });

  it('refuses anything that is not a full sha, so the GitHub link cannot lie', () => {
    // The value comes from whatever built the artifact and ends up in a URL:
    // an abbreviation, a branch name or a path fragment is dropped, not shown.
    for (const junk of ['3d67311', 'main', `${SHA}0`, `../../${SHA}`, 'zzzzzzz' + SHA.slice(7)]) {
      set(undefined, junk);
      expect(buildMeta().commit, junk).toBeNull();
      expect(buildMeta().commitShort, junk).toBeNull();
      expect(buildMeta().commitUrl, junk).toBeNull();
    }
  });
});
