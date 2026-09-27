// SPDX-License-Identifier: AGPL-3.0-only
import { OrkifyChat } from '@orkify/chat/react';
import { CHAT_KLIPY_KEY, CHAT_WIDGET_KEY, CHAT_WIDGET_SRC } from '@/site/config';

/**
 * The support chat, the same widget and the same Discord channel as
 * orkify.com's - Orkitec runs both, and one support queue is enough.
 *
 * `src` is deliberately not the package default. The widget derives the API it
 * calls from the origin of its own script tag (`new URL(script.src).origin` in
 * orkify-chat.js), so the jsDelivr URL the Orkify dashboard suggests would make
 * it request `cdn.jsdelivr.net/api/chat/...`, and a copy served from
 * velorki.com would make it request `/api/chat/...` here, where those routes do
 * not exist. Loading it from orkify.com is also what keeps the rate limits
 * honest: Orkify counts new threads and messages per `cf-connecting-ip`, which
 * behind a proxy of ours would be this server's address for every visitor at
 * once - one new conversation per minute for the whole site.
 *
 * Nothing renders until a widget key is configured, so a fork, a local build
 * and CI get no widget and no third-party request at all. next.config.ts makes
 * the matching Content-Security-Policy conditional on the same variable.
 */
export function SupportChat() {
  if (!CHAT_WIDGET_KEY) return null;
  return (
    <OrkifyChat
      widgetKey={CHAT_WIDGET_KEY}
      {...(CHAT_KLIPY_KEY ? { klipyKey: CHAT_KLIPY_KEY } : {})}
      src={CHAT_WIDGET_SRC}
    />
  );
}
