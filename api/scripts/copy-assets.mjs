// SPDX-License-Identifier: AGPL-3.0-only
//
// tsc only emits .js; the system prompts are .md files that are read at
// startup, so copy them into dist/ after the build.

import { cp } from 'node:fs/promises';

const root = new URL('..', import.meta.url);
await cp(new URL('src/ai/prompts/', root), new URL('dist/ai/prompts/', root), { recursive: true });
console.log('copied src/ai/prompts -> dist/ai/prompts');
