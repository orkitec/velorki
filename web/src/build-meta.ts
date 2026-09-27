// SPDX-License-Identifier: AGPL-3.0-only
/**
 * What this deployment is: the Orkify release number and the commit the
 * artifact was built from.
 *
 * Both arrive as build-time constants, inlined by `next.config.ts` through its
 * `env` block, because neither is knowable at runtime:
 *
 *   - the release number is Orkify's. The agent unpacks the artifact into
 *     `releases/<version>-<artifactId8>` and passes `NEXT_DEPLOYMENT_ID` =
 *     `v<version>-<artifactId8>` into the build (@orkify/cli's DeployExecutor,
 *     step 2c) - and only into the build: `deploy.buildEnv` is not part of the
 *     process environment, so the running workers never see it.
 *   - the commit is not in the artifact either. `orkify deploy upload` packs the
 *     working tree with `.git` excluded, so `git rev-parse` on the box has
 *     nothing to read. CI writes it into `build-info.json` before the upload
 *     (scripts/build-info.mjs), which next.config.ts reads while building.
 *
 * A function and not a constant object so tests can set the environment; after
 * `next build` there is no lookup left either way - `process.env.VELORKI_*` is
 * a string literal in the bundle.
 */
import { GITHUB_URL } from './site/config';

/** Orkify's `NEXT_DEPLOYMENT_ID`: `v<release>-<artifact>`, e.g. `v2-2e703f75`. */
const RELEASE_RE = /^v(\d+)\b/;
/** A commit as git prints it. Full sha from CI; nothing shorter is accepted. */
const COMMIT_RE = /^[0-9a-f]{40}$/;

export type BuildMeta = {
  /** `v2`, or null outside a deployed build (dev, tests, a bare `next build`). */
  release: string | null;
  /** The full 40-character commit, or null when the build did not know it. */
  commit: string | null;
  /** The first seven characters of `commit`, as git and GitHub abbreviate it. */
  commitShort: string | null;
  /** That commit on GitHub, or null when there is no commit to point at. */
  commitUrl: string | null;
};

export function buildMeta(): BuildMeta {
  // Both are validated rather than trusted: they end up in the page's markup
  // and in a github.com URL, and they come from whatever environment built the
  // artifact. React escapes the text; the patterns keep the link honest.
  const release = RELEASE_RE.exec(process.env.VELORKI_RELEASE ?? '');
  const commit = (process.env.VELORKI_COMMIT ?? '').trim().toLowerCase();
  const validCommit = COMMIT_RE.test(commit) ? commit : null;
  return {
    release: release ? `v${release[1]}` : null,
    commit: validCommit,
    commitShort: validCommit ? validCommit.slice(0, 7) : null,
    commitUrl: validCommit ? `${GITHUB_URL}/commit/${validCommit}` : null,
  };
}
