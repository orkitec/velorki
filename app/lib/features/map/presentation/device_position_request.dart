import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/permissions/location_permission.dart';
import '../data/position_provider.dart';
import 'location_rationale_dialog.dart';

/// Asks for when-in-use location the way the map's locate button does — the
/// in-app rationale first, then the system prompt — and answers with one fix.
///
/// Returns `null` when the rider declined, when the permission is denied for
/// good, or when no fix arrives. Both the loop sheet and the assistant need
/// exactly this, and both must not surprise anyone with a bare system prompt,
/// which is why the rationale is part of it.
Future<LatLng?> requestDevicePosition(
  BuildContext context,
  WidgetRef ref,
) async {
  final permissions = ref.read(locationPermissionControllerProvider.notifier);
  var status = await permissions.refresh();
  if (status == LocationPermissionStatus.denied) {
    if (!context.mounted) return null;
    if (!await showLocationRationaleDialog(context)) return null;
    status = await permissions.requestWhenInUse();
  }
  if (status != LocationPermissionStatus.granted) return null;
  final source = ref.read(positionSourceProvider);
  final fix = await source.current() ?? await source.lastKnown();
  return fix == null ? null : LatLng(fix.latitude, fix.longitude);
}
