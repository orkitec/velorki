// SPDX-License-Identifier: AGPL-3.0-only
// The pieces the blog's index, category and author pages share. They use the
// docs index's cards and the site's chips; the blog has no look of its own.
import Link from "next/link";
import { useTranslations } from "next-intl";
import {
  BLOG_CATEGORIES,
  type BlogCategory,
  type BlogPost,
  categoryPath,
  coverImage,
  FEED_PATH,
  formatPostDate,
  postPath,
} from "@/site/blog";
import { localePath } from "@/site/paths";

/**
 * Posts as the docs index lists its pages: one card each, the whole card the
 * link. `locale` is the page's; a post in another language (English on a
 * German index) says so on its link, its title and a small label, so neither
 * a reader nor a crawler mistakes it for a translation.
 *
 * A post with a cover shows it on top of its card, cropped to one shape so the
 * cards in a row line up. Its alt text is empty here: the card's title already
 * says where the link goes, and the full description stays on the post's page.
 */
export function PostList({
  locale,
  posts,
  heading = "h2",
}: {
  locale: string;
  posts: readonly BlogPost[];
  heading?: "h2" | "h3";
}) {
  const t = useTranslations("blog");
  const Heading = heading;
  return (
    <ul className="grid gap-4 sm:grid-cols-2">
      {posts.map((post) => {
        const foreign = post.locale !== locale;
        const cover = coverImage(post);
        return (
          <li key={`${post.locale}/${post.slug}`}>
            <Link
              href={localePath(post.locale, postPath(post))}
              hrefLang={foreign ? post.locale : undefined}
              className="panel block h-full overflow-hidden transition-colors hover:border-accent"
            >
              {cover && (
                // Plain `<img>`, as on the post page: no image optimiser here.
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={cover.src}
                  width={cover.width}
                  height={cover.height}
                  alt=""
                  loading="lazy"
                  decoding="async"
                  className="aspect-[1200/630] w-full border-b border-line object-cover"
                />
              )}
              <div className="p-5">
                <p className="overline flex flex-wrap items-center gap-x-1.5">
                  <time dateTime={post.date}>
                    {formatPostDate(post.date, locale)}
                  </time>
                  <span aria-hidden="true">·</span>
                  <span>{t(`categories.${post.category}`)}</span>
                  {foreign && (
                    <>
                      <span aria-hidden="true">·</span>
                      <span>{t("englishLabel")}</span>
                    </>
                  )}
                </p>
                <Heading
                  className="mt-2 font-display text-2xl"
                  lang={foreign ? post.locale : undefined}
                >
                  {post.title}
                </Heading>
                <p
                  className="mt-2 text-sm text-muted"
                  lang={foreign ? post.locale : undefined}
                >
                  {post.description}
                </p>
              </div>
            </Link>
          </li>
        );
      })}
    </ul>
  );
}

/**
 * The category filter: every post, then one chip per category. Plain links
 * to the category pages, so it works without JavaScript and each filter has
 * an address of its own.
 */
export function CategoryFilter({
  locale,
  current,
}: {
  locale: string;
  current?: BlogCategory;
}) {
  const t = useTranslations("blog");
  const chip = (active: boolean) =>
    `chip transition-colors ${active ? "border-accent text-fg" : "text-muted hover:border-accent hover:text-fg"}`;
  return (
    <nav aria-label={t("filterLabel")} className="mt-8">
      <ul className="flex flex-wrap gap-2">
        <li>
          <Link
            href={localePath(locale, "/blog")}
            aria-current={current === undefined ? "page" : undefined}
            className={chip(current === undefined)}
          >
            {t("all")}
          </Link>
        </li>
        {BLOG_CATEGORIES.map((category) => (
          <li key={category}>
            <Link
              href={localePath(locale, categoryPath(category))}
              aria-current={current === category ? "page" : undefined}
              className={chip(current === category)}
            >
              {t(`categories.${category}`)}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}

/** A visible link to the locale's feed, beside the `<link rel="alternate">` in the head. */
export function FeedLink({ locale }: { locale: string }) {
  const t = useTranslations("blog");
  return (
    <p className="mt-4 text-sm">
      <a
        href={localePath(locale, FEED_PATH)}
        type="application/rss+xml"
        className="text-muted hover:text-fg"
      >
        {t("feed")}
      </a>
    </p>
  );
}
