// SPDX-License-Identifier: AGPL-3.0-only
// The pictures and GPX files beside a blog post, served from the post's own
// folder in content/: `/blog-media/<locale>/<slug>/<hash>/<file>`. Why a
// route and not a copy into public/, and why the hash: see MEDIA_PREFIX in
// src/site/blog.ts. Outside `[locale]` on purpose: the path carries a file
// extension, so the proxy's locale negotiation never sees it, and one address
// serves every language.
import { readMedia } from '@/site/blog';
import { mediaStaticParams } from '@/site/blog-pages';

export function generateStaticParams() {
  return mediaStaticParams();
}

export async function GET(
  _request: Request,
  ctx: { params: Promise<{ locale: string; slug: string; hash: string; file: string }> },
): Promise<Response> {
  const { locale, slug, hash, file } = await ctx.params;
  const media = readMedia(locale, slug, hash, file);
  if (media === null) return new Response('Not found', { status: 404, headers: { 'cache-control': 'no-store' } });
  return new Response(new Uint8Array(media.body), {
    headers: {
      'content-type': media.contentType,
      // The hash in the path changes with the file, so a URL never changes
      // what it answers with.
      'cache-control': 'public, max-age=31536000, immutable',
      ...(media.contentType === 'application/gpx+xml'
        ? { 'content-disposition': `attachment; filename="${file}"` }
        : {}),
    },
  });
}
