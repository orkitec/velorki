// SPDX-License-Identifier: AGPL-3.0-only
// A post's share card when it has no cover of its own: the site's card
// (src/components/OgCard.tsx) with the post's title in the place of the
// tagline. Drawn at build time, one per post, at a path of ours for the reason
// the site's card is (src/app/(site)/[locale]/og-card/route.tsx).
import { ogCardImage } from '@/components/OgCard';
import { findPost } from '@/site/blog';
import { postStaticParams } from '@/site/blog-pages';

export function generateStaticParams() {
  return postStaticParams();
}

export async function GET(
  _request: Request,
  ctx: { params: Promise<{ locale: string; slug: string }> },
): Promise<Response> {
  const { locale, slug } = await ctx.params;
  const post = findPost(locale, slug);
  if (post === null) return new Response('Not found', { status: 404 });
  return ogCardImage(post.title);
}
