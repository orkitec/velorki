import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/place_search_controller.dart';
import '../data/photon_client.dart';
import '../domain/search_result.dart';

/// The planner's place search: a text field with a debounced dropdown.
///
/// The widget only reports the chosen place; what happens with it — a new
/// waypoint or a camera move — is the screen's decision.
class SearchField extends ConsumerStatefulWidget {
  /// Creates the search field.
  const SearchField({required this.onSelected, this.bias, super.key});

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
  bool _dismissed = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            enabled: hasGeocoder,
            decoration: InputDecoration(
              hintText: hasGeocoder ? l10n.searchHint : l10n.searchUnavailable,
              prefixIcon: const Icon(Icons.search),
              border: InputBorder.none,
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
        if (!_dismissed && _controller.text.trim().length >= searchMinChars)
          _ResultsCard(results: results, onSelected: _select),
      ],
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
    return Card(
      margin: const EdgeInsets.only(top: 4),
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
    );
  }
}
