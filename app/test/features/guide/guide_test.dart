import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/guide/domain/guide.dart';

GuidePage _page(String slug, int order, {String? title}) => GuidePage(
  slug: slug,
  title: title ?? slug,
  description: '',
  order: order,
  body: '',
);

void main() {
  group('parseGuidePage', () {
    test('reads the front matter and keeps the body', () {
      final page = parseGuidePage(
        'loops',
        '---\ntitle: Loops\ndescription: "Round trips: from here."\n'
            'order: 4\n---\n\nThe body.\n',
      );
      expect(page.slug, 'loops');
      expect(page.title, 'Loops');
      expect(page.description, 'Round trips: from here.');
      expect(page.order, 4);
      expect(page.body.trim(), 'The body.');
    });

    test('a page without order or description still parses', () {
      final page = parseGuidePage('x', '---\ntitle: X\n---\nBody');
      expect(page.description, '');
      expect(page.body, 'Body');
      expect(sortGuidePages([page, _page('y', 3)]).map((p) => p.slug), [
        'y',
        'x',
      ]);
    });

    test('no front matter or no title is an error', () {
      expect(
        () => parseGuidePage('x', 'Just text'),
        throwsA(isA<GuideFormatException>()),
      );
      expect(
        () => parseGuidePage('x', '---\norder: 1\n---\nBody'),
        throwsA(isA<GuideFormatException>()),
      );
    });
  });

  test('pages sort by order, then by title', () {
    final sorted = sortGuidePages([
      _page('c', 2),
      _page('b', 1, title: 'B'),
      _page('a', 1, title: 'A'),
    ]);
    expect(sorted.map((p) => p.slug), ['a', 'b', 'c']);
  });

  test('a locale falls back to English page by page', () {
    final merged = mergeGuideLocales(
      english: [
        _page('one', 1, title: 'One'),
        _page('two', 2, title: 'Two'),
      ],
      locale: [_page('two', 2, title: 'Zwei')],
    );
    expect(merged.map((p) => p.title), ['One', 'Zwei']);
  });

  group('resolveGuideLink', () {
    test('./slug and ./slug#anchor are guide pages', () {
      expect(resolveGuideLink('./loops', 'en'), const GuidePageLink('loops'));
      expect(
        resolveGuideLink('./navigation#wenn-du-die-route-verl%C3%A4sst', 'de'),
        const GuidePageLink('navigation', 'wenn-du-die-route-verlässt'),
      );
      expect(
        resolveGuideLink('#the-place-card', 'en'),
        const GuidePageLink(null, 'the-place-card'),
      );
    });

    test('a site path opens the website in the page\'s language', () {
      expect(
        resolveGuideLink('/privacy', 'en'),
        ExternalLink(Uri.parse('https://velorki.com/privacy')),
      );
      expect(
        resolveGuideLink('/privacy', 'de'),
        ExternalLink(Uri.parse('https://velorki.com/de/privacy')),
      );
    });

    test('other addresses open outside the app', () {
      expect(
        resolveGuideLink('https://github.com/orkitec/velorki', 'en'),
        ExternalLink(Uri.parse('https://github.com/orkitec/velorki')),
      );
      expect(
        resolveGuideLink('mailto:ride@velorki.com', 'fr'),
        ExternalLink(Uri.parse('mailto:ride@velorki.com')),
      );
      expect(resolveGuideLink('', 'en'), isNull);
      expect(resolveGuideLink('loops', 'en'), isNull);
    });
  });

  group('headingAnchor', () {
    test('makes the ids the website makes', () {
      final seen = <String, int>{};
      expect(
        headingAnchor('When you leave the route', seen),
        'when-you-leave-the-route',
      );
      expect(
        headingAnchor('Quand vous quittez l’itinéraire', seen),
        'quand-vous-quittez-litinéraire',
      );
      expect(
        headingAnchor('Synchronisierung mit iCloud oder Google Drive', seen),
        'synchronisierung-mit-icloud-oder-google-drive',
      );
      expect(headingAnchor('Battery (Android)', seen), 'battery-android');
    });

    test('a repeated heading gets a number', () {
      final seen = <String, int>{};
      expect(headingAnchor('Location', seen), 'location');
      expect(headingAnchor('Location', seen), 'location-1');
      expect(headingAnchor('Location', seen), 'location-2');
    });
  });

  test('a body splits at its headings, not inside code', () {
    final sections = splitGuideSections(
      'Intro.\n\n## First\n\nText.\n\n```\n# not a heading\n```\n\n'
      '### The `code` one\n\nMore.\n',
    );
    expect(sections.map((s) => s.anchor), [null, 'first', 'the-code-one']);
    expect(sections[1].markdown, contains('# not a heading'));
    expect(sections[2].markdown, startsWith('### The `code` one'));
  });
}
