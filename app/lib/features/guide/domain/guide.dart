import 'package:yaml/yaml.dart';

import '../../../core/links/velorki_urls.dart';

/// One page of the user guide: a Markdown file of the website's
/// `web/content/<locale>/docs/`, bundled by `tool/gen.sh`.
class GuidePage {
  /// Creates a page.
  const GuidePage({
    required this.slug,
    required this.title,
    required this.description,
    required this.order,
    required this.body,
  });

  /// The file name without `.md`, as the website's path and `./slug` links
  /// name it.
  final String slug;

  /// The front matter's `title`.
  final String title;

  /// The front matter's `description`, empty when it has none.
  final String description;

  /// The front matter's `order`; pages without one go last.
  final int order;

  /// The Markdown after the front matter.
  final String body;
}

/// A guide file could not be read.
class GuideFormatException implements Exception {
  /// Creates the exception for [slug].
  const GuideFormatException(this.slug, this.reason);

  /// The page that failed.
  final String slug;

  /// What was wrong with it.
  final String reason;

  @override
  String toString() => 'GuideFormatException($slug): $reason';
}

final _frontMatter = RegExp(r'^---\r?\n([\s\S]*?)\r?\n---\r?\n?');

/// Parses [text], a guide file named [slug]: the YAML front matter between
/// `---` lines, then the Markdown body.
GuidePage parseGuidePage(String slug, String text) {
  final match = _frontMatter.firstMatch(text);
  if (match == null) {
    throw GuideFormatException(slug, 'no front matter');
  }
  final Object? meta = loadYaml(match.group(1)!);
  if (meta is! YamlMap) {
    throw GuideFormatException(slug, 'front matter is not a map');
  }
  final title = meta['title'];
  if (title is! String || title.trim().isEmpty) {
    throw GuideFormatException(slug, 'no title');
  }
  final description = meta['description'];
  final order = meta['order'];
  return GuidePage(
    slug: slug,
    title: title.trim(),
    description: description is String ? description.trim() : '',
    order: order is int ? order : 1 << 30,
    body: text.substring(match.end),
  );
}

/// [pages] in the order the website lists them: by `order`, then by title.
List<GuidePage> sortGuidePages(Iterable<GuidePage> pages) =>
    pages.toList()..sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.title.compareTo(b.title);
    });

/// The pages of [locale] with English's for any [locale] has not got, in
/// order: the guide in the app's language, falling back page by page.
List<GuidePage> mergeGuideLocales({
  required Iterable<GuidePage> english,
  required Iterable<GuidePage> locale,
}) {
  final bySlug = <String, GuidePage>{
    for (final page in english) page.slug: page,
    for (final page in locale) page.slug: page,
  };
  return sortGuidePages(bySlug.values);
}

/// Where a link in a guide page leads.
sealed class GuideLinkTarget {
  const GuideLinkTarget();
}

/// Another guide page, or a heading on one: `./slug`, `./slug#anchor`, or
/// `#anchor` on the page itself ([slug] `null`).
final class GuidePageLink extends GuideLinkTarget {
  /// Creates the link.
  const GuidePageLink(this.slug, [this.anchor]);

  /// The page, `null` for the page the link is on.
  final String? slug;

  /// The heading's id, as [headingAnchor] makes it.
  final String? anchor;

  @override
  bool operator ==(Object other) =>
      other is GuidePageLink && other.slug == slug && other.anchor == anchor;

  @override
  int get hashCode => Object.hash(slug, anchor);

  @override
  String toString() => 'GuidePageLink($slug, $anchor)';
}

/// Anything else, opened outside the app: the website's own pages, other
/// sites, mail.
final class ExternalLink extends GuideLinkTarget {
  /// Creates the link.
  const ExternalLink(this.url);

  /// The address to open.
  final Uri url;

  @override
  bool operator ==(Object other) => other is ExternalLink && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'ExternalLink($url)';
}

/// Where [href], a link in a guide page in [languageCode], leads; `null`
/// when it is not a link at all.
///
/// A site-absolute path goes to the website in the page's language
/// ([velorkiSiteUrl]).
GuideLinkTarget? resolveGuideLink(String href, String languageCode) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('#')) {
    return GuidePageLink(null, _anchor(trimmed.substring(1)));
  }
  if (trimmed.startsWith('./')) {
    final rest = trimmed.substring(2);
    final hash = rest.indexOf('#');
    final slug = hash < 0 ? rest : rest.substring(0, hash);
    final anchor = hash < 0 ? null : _anchor(rest.substring(hash + 1));
    return GuidePageLink(
      slug.endsWith('.md') ? slug.substring(0, slug.length - 3) : slug,
      anchor,
    );
  }
  if (trimmed.startsWith('/') && !trimmed.startsWith('//')) {
    return ExternalLink(
      Uri.parse(velorkiSiteUrl(languageCode, trimmed.substring(1))),
    );
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return null;
  return ExternalLink(uri);
}

String? _anchor(String raw) {
  if (raw.isEmpty) return null;
  try {
    return Uri.decodeComponent(raw);
  } on ArgumentError {
    return raw;
  }
}

/// Everything github-slugger (the website's `rehype-slug`) drops from a
/// heading: whatever is not a letter, mark, digit, connector, space or
/// hyphen.
final _notInSlug = RegExp(r'[^\p{L}\p{M}\p{N}\p{Pc} -]', unicode: true);

/// The id the website gives a heading [text]: lower-cased, punctuation
/// dropped, spaces turned to hyphens. The first repeat of an id gets `-1`,
/// the next `-2`, as on the site; [seen] carries the ids so far.
String headingAnchor(String text, Map<String, int> seen) {
  final base = text
      .toLowerCase()
      .replaceAll(_notInSlug, '')
      .replaceAll(' ', '-');
  var id = base;
  while (seen.containsKey(id)) {
    seen[base] = seen[base]! + 1;
    id = '$base-${seen[base]}';
  }
  seen[id] = 0;
  return id;
}

/// A stretch of a page's body from one heading to the next: what the page
/// screen can scroll to.
class GuideSection {
  /// Creates a section.
  const GuideSection(this.anchor, this.markdown);

  /// The id of the heading the section starts with, `null` for the text
  /// before the first heading.
  final String? anchor;

  /// The section's Markdown, its heading included.
  final String markdown;
}

final _heading = RegExp(r'^#{1,6}[ \t]+(.*?)[ \t#]*$');
final _fence = RegExp(r'^\s*(```|~~~)');

/// [body] cut at every ATX heading outside a code block, each part with its
/// heading's id.
List<GuideSection> splitGuideSections(String body) {
  final sections = <GuideSection>[];
  final seen = <String, int>{};
  String? anchor;
  final lines = <String>[];
  var inFence = false;

  void flush() {
    final text = lines.join('\n').trim();
    if (text.isNotEmpty || anchor != null) {
      sections.add(GuideSection(anchor, text));
    }
    lines.clear();
  }

  for (final line in body.split('\n')) {
    if (_fence.hasMatch(line)) inFence = !inFence;
    final heading = inFence ? null : _heading.firstMatch(line);
    if (heading != null) {
      flush();
      anchor = headingAnchor(_plainText(heading.group(1)!), seen);
    }
    lines.add(line);
  }
  flush();
  return sections;
}

/// A heading's text as it reads, without Markdown's emphasis, code and link
/// syntax: what the site's slug is made from.
String _plainText(String markdown) => markdown
    .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
    .replaceAll(RegExp('[*`]'), '');
