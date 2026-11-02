import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/links/link_opener.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/error_text.dart';
import '../../shared/presentation/wide_panel.dart';
import '../data/guide_repository.dart';
import '../domain/guide.dart';

void _showGuidePage(BuildContext context, String slug, {String? anchor}) =>
    unawaited(
      Navigator.of(context).push(
        ColumnPageRoute<void>(
          builder: (_) => GuidePageScreen(slug: slug, anchor: anchor),
        ),
      ),
    );

/// Settings → Guide: the guide's pages in the app's language, read from the
/// bundle, so the website's user guide is there without a connection.
class GuideContents extends ConsumerWidget {
  /// Creates the list.
  const GuideContents({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    return switch (ref.watch(guideProvider(languageCode))) {
      AsyncData(:final value) => Column(
        children: [
          for (final page in value)
            ListTile(
              key: ValueKey<String>(page.slug),
              title: Text(page.title),
              subtitle: page.description.isEmpty
                  ? null
                  : Text(page.description),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showGuidePage(context, page.slug),
            ),
        ],
      ),
      AsyncError(:final error) => _Failure(errorText(l10n, error)),
      _ => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

/// One page of the guide, scrolled to [anchor]'s heading when it has one.
class GuidePageScreen extends ConsumerStatefulWidget {
  /// Creates the page for [slug].
  const GuidePageScreen({required this.slug, this.anchor, super.key});

  /// The page's file name, as `./slug` links name it.
  final String slug;

  /// The heading to open at, as the website's ids are.
  final String? anchor;

  @override
  ConsumerState<GuidePageScreen> createState() => _GuidePageScreenState();
}

class _GuidePageScreenState extends ConsumerState<GuidePageScreen> {
  final Map<String, GlobalKey> _headings = {};
  bool _scrolled = false;

  void _scrollTo(String? anchor) {
    final target = _headings[anchor]?.currentContext;
    if (target == null) return;
    unawaited(
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _tapLink(String? href) async {
    if (href == null) return;
    final languageCode = Localizations.localeOf(context).languageCode;
    switch (resolveGuideLink(href, languageCode)) {
      case null:
        return;
      case GuidePageLink(:final slug, :final anchor):
        if (slug == null || slug == widget.slug) {
          _scrollTo(anchor);
        } else {
          _showGuidePage(context, slug, anchor: anchor);
        }
      case ExternalLink(:final url):
        final l10n = AppLocalizations.of(context);
        final messenger = ScaffoldMessenger.of(context);
        final opened = await ref.read(linkOpenerProvider)(url);
        if (opened) return;
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsOpenFailed)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final pages = ref.watch(guideProvider(languageCode));
    final page = pages.value?.where((p) => p.slug == widget.slug).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(page?.title ?? l10n.settingsGuide)),
      body: switch (pages) {
        AsyncData() when page != null => _body(context, page),
        AsyncError(:final error) => _Failure(errorText(l10n, error)),
        AsyncData() => _Failure(l10n.errorUnexpected),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(BuildContext context, GuidePage page) {
    final sections = splitGuideSections(page.body);
    final style = _guideMarkdownStyle(Theme.of(context));
    if (!_scrolled && widget.anchor != null) {
      _scrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollTo(widget.anchor);
      });
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.paddingOf(context).bottom + 32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in sections)
            MarkdownBody(
              key: section.anchor == null
                  ? null
                  : _headings.putIfAbsent(section.anchor!, GlobalKey.new),
              data: section.markdown,
              styleSheet: style,
              onTapLink: (_, href, _) => unawaited(_tapLink(href)),
            ),
        ],
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

/// A column no wider than [max], or than its widest cell if that is less;
/// an [IntrinsicColumnWidth] so the table scrolls sideways when the columns
/// add up to more than the screen.
class _CappedColumnWidth extends IntrinsicColumnWidth {
  const _CappedColumnWidth(this.max);

  final double max;

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    final width = super.minIntrinsicWidth(cells, containerWidth);
    return width < max ? width : max;
  }

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    final width = super.maxIntrinsicWidth(cells, containerWidth);
    return width < max ? width : max;
  }
}

/// The guide's Markdown in the app's type and colours.
MarkdownStyleSheet _guideMarkdownStyle(ThemeData theme) {
  final text = theme.textTheme;
  final colors = theme.colorScheme;
  final body = text.bodyLarge?.copyWith(height: 1.5);
  final code = text.bodyMedium?.copyWith(
    fontFamily: 'monospace',
    backgroundColor: colors.surfaceContainerHighest,
  );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    pPadding: const EdgeInsets.only(bottom: 4),
    listBullet: body,
    a: TextStyle(
      color: colors.primary,
      decoration: TextDecoration.underline,
      decorationColor: colors.primary,
    ),
    strong: const TextStyle(fontWeight: FontWeight.w700),
    code: code,
    h1: text.headlineSmall,
    h2: text.titleLarge,
    h2Padding: const EdgeInsets.only(top: 20, bottom: 4),
    h3: text.titleMedium,
    h3Padding: const EdgeInsets.only(top: 12, bottom: 2),
    h4: text.titleSmall,
    blockSpacing: 12,
    blockquote: body?.copyWith(color: colors.onSurfaceVariant),
    blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    blockquoteDecoration: BoxDecoration(
      color: colors.surfaceContainerHighest,
      border: Border(left: BorderSide(color: colors.primary, width: 3)),
    ),
    codeblockDecoration: BoxDecoration(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    tableHead: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
    tableBody: text.bodyMedium,
    tableHeadAlign: TextAlign.start,
    tableBorder: TableBorder.all(color: colors.outlineVariant),
    tableColumnWidth: const _CappedColumnWidth(260),
    tableCellsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    tableHeadCellsDecoration: BoxDecoration(
      color: colors.surfaceContainerHighest,
    ),
    tableVerticalAlignment: TableCellVerticalAlignment.top,
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.outlineVariant)),
    ),
  );
}
