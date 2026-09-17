// SPDX-License-Identifier: AGPL-3.0-only
import { existsSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { PROMPT_DIR, loadPrompts } from '@/ai/provider';

describe('system prompts', () => {
  it('resolves the prompt directory from the project root', () => {
    expect(PROMPT_DIR.endsWith('/src/ai/prompts')).toBe(true);
    expect(existsSync(PROMPT_DIR)).toBe(true);
  });

  it('loads both prompts without their SPDX header', () => {
    const prompts = loadPrompts();
    expect(prompts.plan).toContain('propose_route');
    expect(prompts.describe).toContain('60 to 90 words');
    expect(prompts.plan.startsWith('<!--')).toBe(false);
    expect(prompts.describe.startsWith('<!--')).toBe(false);
    expect(prompts.plan).not.toContain('SPDX-License-Identifier');
    expect(prompts.describe).not.toContain('SPDX-License-Identifier');
  });
});
