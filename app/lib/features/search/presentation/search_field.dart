import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/place_search_controller.dart';
import '../data/photon_client.dart';
import '../domain/search_result.dart';

/// The planner's place search: a text field with a debounced dropdown.
///
/// The widget only reports the chosen place; what happens with it — a new
/// waypoint or a camera move — is the screen's decision.
class SearchField extends ConsumerStatefulWidget {
  /// Creates the search field.
  const SearchField({
    required this.onSelected,
    this.bias,
    this.onCleared,
    this.onFocusChanged,
    super.key,
  });

  /// Called when the field takes or gives up focus, before the keyboard
  /// moves: the screen can make room for it.
  final ValueChanged<bool>? onFocusChanged;

  /// Called when the rider clears the field or edits it after picking a
  /// result: the picked place is no longer what the field says.
  final VoidCallback? onCleared;

  /// Called with the place the user picked.
  final ValueChanged<SearchResult> onSelected;

  /// The current map centre, read when a request goes out.
  final LatLng? Function()? bias;

  @override
  ConsumerState<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<SearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  // The results float in the app's overlay, anchored under the field, so
  // nothing on the screen (the planner sheet, for one) can cover them.
  final LayerLink _link = LayerLink();
  final OverlayPortalController _results = OverlayPortalController();
  double _fieldWidth = 0;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
  }

  void _onFocus() => widget.onFocusChanged?.call(_focusNode.hasFocus);

  @override
  void dispose() {
    _controller.dispose();
    _focusNode
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  bool get _showResults =>
      !_dismissed && _controller.text.trim().length >= searchMinChars;

  void _syncResults() {
    if (_showResults) {
      if (!_results.isShowing) _results.show();
    } else if (_results.isShowing) {
      _results.hide();
    }
  }

  void _onChanged(String text) {
    // Typing over a picked result unpicks it: the pin on the map must not
    // outlive the words that put it there.
    if (_dismissed) widget.onCleared?.call();
    setState(() => _dismissed = false);
    ref
        .read(placeSearchProvider.notifier)
        .query(
          text,
          lang: Localizations.localeOf(context).languageCode,
          bias: widget.bias?.call(),
        );
  }

  void _clear() {
    _controller.clear();
    ref.read(placeSearchProvider.notifier).clear();
    setState(() => _dismissed = false);
    widget.onCleared?.call();
  }

  void _select(SearchResult result) {
    _controller.text = result.name;
    _focusNode.unfocus();
    setState(() => _dismissed = true);
    widget.onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final results = ref.watch(placeSearchProvider);
    final hasGeocoder = ref.watch(photonClientProvider) != null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncResults();
    });
    return LayoutBuilder(
      builder: (context, constraints) {
        _fieldWidth = constraints.maxWidth;
        return OverlayPortal(
          controller: _results,
          overlayChildBuilder: (context) => Positioned(
            width: _fieldWidth,
            child: CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              showWhenUnlinked: false,
              child: Material(
                type: MaterialType.transparency,
                child: _ResultsCard(results: results, onSelected: _select),
              ),
            ),
          ),
          child: CompositedTransformTarget(
            link: _link,
            child: GlassPanel(
              radius: 28,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                enabled: hasGeocoder,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: hasGeocoder
                      ? l10n.searchHint
                      : l10n.searchUnavailable,
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.searchClear,
                          icon: const Icon(Icons.close),
                          onPressed: _clear,
                        ),
                ),
                onChanged: _onChanged,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({required this.results, required this.onSelected});

  final AsyncValue<List<SearchResult>> results;
  final ValueChanged<SearchResult> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      // Opaque: it floats over the chips and the sheet, and a list read
      // through them is not a list.
      child: Material(
        color: scheme.surfaceContainerLowest,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: results.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (error, _) => ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(
                error is SearchException && error.message.contains('configured')
                    ? l10n.searchUnavailable
                    : l10n.searchFailed,
              ),
              // The reason, so a failure is diagnosable from the screen.
              subtitle:
                  error is SearchException &&
                      !error.message.contains('configured')
                  ? Text(
                      error.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
            ),
            data: (items) => items.isEmpty
                ? ListTile(title: Text(l10n.searchNoResults))
                : ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final r = items[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(r.name),
                        subtitle: r.subtitle.isEmpty ? null : Text(r.subtitle),
                        onTap: () => onSelected(r),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
