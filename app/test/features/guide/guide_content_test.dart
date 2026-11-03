import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:velorki/features/guide/domain/guide.dart';
import 'package:yaml/yaml.dart';

/// The website's guide, which `tool/gen.sh` bundles: read where it is
/// written, so a broken link in any translation fails here before it ships.
void main() {
  final content = Directory(p.join('..', 'web', 'content'));
  final locales = [
    for (final dir in content.listSync().whereType<Directory>())
      if (Directory(p.join(dir.path, 'docs')).existsSync())
        p.basename(dir.path),
  ]..sort();

  List<GuidePage> pagesOf(String locale) => [
    for (final file in Directory(
      p.join(content.path, locale, 'docs'),
    ).listSync().whereType<File>())
      if (file.path.endsWith('.md'))
        parseGuidePage(
          p.basenameWithoutExtension(file.path),
          file.readAsStringSync(),
        ),
  ];

  bool isDraft(String locale, String slug) =>
      RegExp(r'^draft:\s*true\s*$', multiLine: true).hasMatch(
        File(p.join(content.path, locale, 'docs', '$slug.md'))
            .readAsStringSync()
            .split('\n---')
            .first,
      );

  test('every locale has a guide and pubspec.yaml bundles it', () {
    expect(locales, contains('en'));
    final assets =
        (loadYaml(File('pubspec.yaml').readAsStringSync())
                as YamlMap)['flutter']['assets']
            as YamlList;
    for (final locale in locales) {
      expect(assets, contains('assets/guide/$locale/'), reason: locale);
    }
  });

  final english = pagesOf('en').where((p) => !isDraft('en', p.slug));
  for (final locale in locales) {
    test('the $locale guide parses and its links lead to its own pages '
        'and headings', () {
      final own = pagesOf(locale).where((p) => !isDraft(locale, p.slug));
      final pages = mergeGuideLocales(english: english, locale: own);
      final slugs = {for (final page in pages) page.slug};
      // Each page's heading ids, as the website makes them.
      final anchors = {
        for (final page in pages)
          page.slug: {
            for (final section in splitGuideSections(page.body))
              ?section.anchor,
          },
      };
      final link = RegExp(r'\]\(([^)\s]+)\)');
      for (final page in pages) {
        expect(page.title, isNotEmpty, reason: '$locale/${page.slug}');
        for (final match in link.allMatches(page.body)) {
          final target = resolveGuideLink(match.group(1)!, locale);
          expect(
            target,
            isNotNull,
            reason: '$locale/${page.slug}: ${match.group(1)}',
          );
          if (target case GuidePageLink(:final slug, :final anchor)) {
            final to = slug ?? page.slug;
            expect(
              slugs,
              contains(to),
              reason: '$locale/${page.slug} links to ./$to',
            );
            if (anchor != null) {
              expect(
                anchors[to],
                contains(anchor),
                reason: '$locale/${page.slug} links to ./$to#$anchor',
              );
            }
          }
        }
      }
    });
  }
}
