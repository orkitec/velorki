// SPDX-License-Identifier: AGPL-3.0-only
import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

/**
 * The support chat is Orkify's widget loaded from orkify.com. Two properties
 * matter and neither is visible in the rendered markup, because the widget
 * injects its script from an effect: that nothing is rendered without a widget
 * key, and that the script URL stays the one whose origin serves the chat API.
 */
afterEach(() => {
  vi.resetModules();
  vi.unstubAllEnvs();
});

async function load() {
  const [{ SupportChat }, config] = await Promise.all([
    import('@/components/SupportChat'),
    import('@/site/config'),
  ]);
  return { SupportChat, config };
}

describe('support chat', () => {
  it('renders nothing when no widget key was configured', async () => {
    vi.stubEnv('NEXT_PUBLIC_CHAT_WIDGET_KEY', '');
    const { SupportChat } = await load();
    expect(SupportChat()).toBeNull();
    expect(renderToStaticMarkup(<SupportChat />)).toBe('');
  });

  it('passes the key, the sticker key and the script URL to the widget', async () => {
    vi.stubEnv('NEXT_PUBLIC_CHAT_WIDGET_KEY', 'wk_abcdef0123456789');
    vi.stubEnv('NEXT_PUBLIC_KLIPY_API_KEY', 'klipy-test');
    const { SupportChat } = await load();
    const element = SupportChat() as { props: Record<string, unknown> };
    expect(element.props).toMatchObject({
      widgetKey: 'wk_abcdef0123456789',
      klipyKey: 'klipy-test',
      src: 'https://orkify.com/orkify-chat.js',
    });
  });

  it('leaves the sticker key out entirely when there is none', async () => {
    vi.stubEnv('NEXT_PUBLIC_CHAT_WIDGET_KEY', 'wk_abcdef0123456789');
    vi.stubEnv('NEXT_PUBLIC_KLIPY_API_KEY', '');
    const { SupportChat } = await load();
    const element = SupportChat() as { props: Record<string, unknown> };
    expect(element.props).not.toHaveProperty('klipyKey');
  });

  it('serves the script from the host that answers its API calls', async () => {
    // The widget reads its API base from its own script origin, so this URL is
    // load-bearing: jsDelivr (the package default) or a copy on velorki.com
    // would both point the chat API at a host that has no /api/chat routes.
    const { config } = await load();
    expect(new URL(config.CHAT_WIDGET_SRC).origin).toBe('https://orkify.com');
  });
});
