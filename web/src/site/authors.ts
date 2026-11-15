// SPDX-License-Identifier: AGPL-3.0-only
// The people who write on the blog. A post names its author by id in the front
// matter (`author: steffen`); the loader in blog.ts refuses an id that is not
// here, so a typo fails the build instead of rendering a post with no byline.
//
// `url` is where the person is on the web; `sameAs` is every profile that is
// the same person, for the Person in a post's JSON-LD.

export interface Author {
  id: string;
  name: string;
  /** One line under the name on the author page. English, like the names. */
  role: string;
  url: string;
  sameAs: readonly string[];
}

export const AUTHORS: Readonly<Record<string, Author>> = {
  steffen: {
    id: 'steffen',
    name: 'Steffen Römer',
    role: 'Builds Velorki',
    url: 'https://github.com/steffen-roemer',
    sameAs: ['https://github.com/steffen-roemer'],
  },
};

/** Every author id, for the author pages' static params. */
export const AUTHOR_IDS: readonly string[] = Object.keys(AUTHORS);

export function findAuthor(id: string): Author | null {
  return Object.hasOwn(AUTHORS, id) ? AUTHORS[id]! : null;
}
