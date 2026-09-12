import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';
import '../../shared/presentation/placeholder_body.dart';
import '../application/external_route_importer.dart';
import '../application/external_routes_loader.dart';
import '../common/domain/connected_account.dart';
import '../common/domain/external_route.dart';
import '../common/domain/integration_exception.dart';
import 'integration_labels.dart';

/// The routes of a connected partner account, with an Import action each.
///
/// One screen for both services: Strava and Ride with GPS describe a route
/// with the same numbers, and the cache policy — drop the list after seven
/// days, which is Strava's rule — is applied to both.
class ExternalRoutesScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [service].
  const ExternalRoutesScreen({required this.service, super.key});

  /// Whose routes are listed.
  final IntegrationService service;

  @override
  ConsumerState<ExternalRoutesScreen> createState() =>
      _ExternalRoutesScreenState();
}

class _ExternalRoutesScreenState extends ConsumerState<ExternalRoutesScreen> {
  bool _loading = true;
  String? _error;
  List<ExternalRoute> _routes = const <ExternalRoute>[];
  DateTime? _fetchedAt;
  String? _importing;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final loader = ref.read(externalRoutesLoaderProvider(widget.service));
    if (loader == null) {
      setState(() {
        _loading = false;
        _error = null;
        _routes = const <ExternalRoute>[];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await loader.load(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _routes = result.routes;
        _fetchedAt = result.fetchedAt;
      });
    } on IntegrationException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _import(ExternalRoute route) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final loader = ref.read(externalRoutesLoaderProvider(widget.service));
    if (loader == null) return;
    setState(() => _importing = route.id);
    try {
      final gpx = await loader.gpx(route.id);
      await ref
          .read(externalRouteImporterProvider)
          .importRoute(
            service: widget.service,
            gpx: gpx,
            externalId: route.id,
            name: route.name,
          );
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.externalRoutesImported(route.name))),
      );
    } on IntegrationException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.externalRoutesImportFailed(e.message))),
      );
    } finally {
      if (mounted) setState(() => _importing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = serviceLabel(l10n, widget.service);
    final connected =
        ref.watch(externalRoutesLoaderProvider(widget.service)) != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.externalRoutesTitle(label)),
        actions: [
          IconButton(
            onPressed: _loading || !connected
                ? null
                : () => unawaited(_load(forceRefresh: true)),
            icon: const Icon(Icons.refresh),
            tooltip: l10n.externalRoutesRefresh,
          ),
        ],
      ),
      body: _body(l10n, label, connected: connected),
    );
  }

  Widget _body(AppLocalizations l10n, String label, {required bool connected}) {
    if (!connected) {
      return PlaceholderBody(
        icon: Icons.link_off,
        message: l10n.externalRoutesNotConnected(label),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) {
      return PlaceholderBody(
        icon: Icons.error_outline,
        message: l10n.externalRoutesFailed(error),
      );
    }
    if (_routes.isEmpty) {
      return PlaceholderBody(
        icon: Icons.route_outlined,
        message: l10n.externalRoutesEmpty(label),
      );
    }
    final fetchedAt = _fetchedAt;
    return ListView.separated(
      itemCount: _routes.length + (fetchedAt == null ? 0 : 1),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (fetchedAt != null && index == _routes.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.externalRoutesFetchedAt(formatDate(l10n, fetchedAt)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        final route = _routes[index];
        return ListTile(
          leading: const Icon(Icons.route_outlined),
          title: Text(route.name),
          subtitle: Text(
            l10n.externalRouteSubtitle(
              formatDistance(l10n, route.distanceM),
              formatHeight(l10n, route.elevationGainM),
              route.createdAt == null ? '' : formatDate(l10n, route.createdAt!),
            ),
          ),
          trailing: _importing == route.id
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _importing != null
                      ? null
                      : () => unawaited(_import(route)),
                  child: Text(l10n.externalRoutesImport),
                ),
        );
      },
    );
  }
}

/// Opens the route list of [service] on top of whatever is showing.
Future<void> openExternalRoutes(
  BuildContext context,
  IntegrationService service,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => ExternalRoutesScreen(service: service),
  ),
);
