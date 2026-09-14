import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/data/route_repository.dart';
import '../../recording/application/recording_controller.dart';
import '../../recording/domain/recording_snapshot.dart';
import '../data/navigation_settings.dart';
import '../data/turn_speaker.dart';
import '../domain/navigation_progress.dart';
import '../presentation/turn_phrases.dart';
import 'turn_announcer.dart';
import 'turn_navigator.dart';

part 'navigation_controller.g.dart';

/// The route a ride is being guided along, plus a key that says when it is a
/// different route from the one before.
@immutable
class GuidedRoute {
  /// Creates the route.
  const GuidedRoute({
    required this.key,
    required this.line,
    required this.turns,
  });

  /// Identity of the route: the saved route's id, or, for a plan that was
  /// never saved, the shape of its geometry.
  final String key;

  /// The geometry the rider is matched against.
  final List<LatLng> line;

  /// The turn instructions anchored to [line].
  final List<TurnHint> turns;
}

/// The route the record screen draws and the navigator follows: the saved
/// route the rider chose, or the plan on the Plan tab when they chose none.
///
/// A provider of its own because the saved route is a family whose argument
/// changes while the app runs; this one is allowed to rebuild, so the
/// navigation controller below never has to.
@Riverpod(keepAlive: true)
GuidedRoute? guidedRoute(Ref ref) {
  final followed = ref.watch(
    recordingControllerProvider.select((s) => s.followedRouteId),
  );
  if (followed != null) {
    final route = ref.watch(savedRouteProvider(followed)).value;
    if (route == null) return null;
    final line = route.geometry.map((p) => p.pos).toList(growable: false);
    return GuidedRoute(
      key: 'saved:${route.id}',
      line: line,
      turns: route.turns,
    );
  }
  final result = ref.watch(plannerControllerProvider.select((s) => s.result));
  final line = result?.positions ?? const <LatLng>[];
  if (result == null || line.isEmpty) return null;
  // A plan has no id, so its shape stands in for one: a re-route always
  // changes the point count or one of the ends.
  return GuidedRoute(
    key: 'plan:${line.length}:${line.first}:${line.last}',
    line: line,
    turns: result.turns,
  );
}

/// The localisations the spoken cues are built from.
///
/// The controller has no [BuildContext], so it looks the strings up by the
/// platform locale instead. A locale the app has no translation for falls back
/// to English. Tests override this provider to pin the language.
@Riverpod(keepAlive: true)
AppLocalizations navigationLocalizations(Ref ref) {
  try {
    return lookupAppLocalizations(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
  } catch (_) {
    return lookupAppLocalizations(const Locale('en'));
  }
}

/// Where the rider is on the guided route, or `null` when nothing is guided.
///
/// Everything here is driven by listeners rather than by `ref.watch`: the
/// controller writes its own state on every position fix, and watching the
/// recorder would rebuild it in a loop. It is kept alive for the whole session
/// so a ride keeps its navigator while the rider is on another tab; `HomeShell`
/// reads it once so that session actually starts.
@Riverpod(keepAlive: true)
class NavigationController extends _$NavigationController {
  TurnNavigator? _navigator;
  TurnAnnouncer? _announcer;

  /// Identity of the route the navigator was built for.
  String? _routeKey;

  /// The snapshot already fed to the navigator, so a settings change does not
  /// run the same fix through the announcer twice.
  RecordingSnapshot? _fedSnapshot;

  /// The last progress, mirrored here because `state` cannot be read while
  /// the notifier is building.
  NavigationProgress? _progress;

  /// Whether guidance was running on the previous pass, so the speaker is
  /// silenced exactly once when it stops.
  bool _guiding = false;

  @override
  NavigationProgress? build() {
    ref.listen(recordingControllerProvider, (previous, next) => _refresh());
    ref.listen(navigationSettingsProvider, (previous, next) => _refresh());
    ref.listen(guidedRouteProvider, (previous, next) => _refresh());
    ref.onDispose(_forget);
    return _compute();
  }

  void _refresh() => state = _compute();

  /// Works out the progress for whatever the recorder, the settings and the
  /// route say right now.
  NavigationProgress? _compute() {
    final recording = ref.read(recordingControllerProvider);
    final settings = ref.read(navigationSettingsProvider);
    final route = ref.read(guidedRouteProvider);
    final guided =
        recording.isRecording &&
        settings.turns &&
        (route?.line.length ?? 0) >= 2;
    if (!guided || route == null) {
      _stop();
      return null;
    }

    if (route.key != _routeKey) {
      _routeKey = route.key;
      _navigator = TurnNavigator(line: route.line, turns: route.turns);
      _announcer = TurnAnnouncer();
      _fedSnapshot = null;
      _progress = null;
    }
    _guiding = true;

    final snapshot = recording.snapshot;
    final position = snapshot?.lastPosition;
    // Nothing new to match: keep showing what the last fix said.
    if (snapshot == null ||
        position == null ||
        identical(snapshot, _fedSnapshot)) {
      return _progress;
    }
    _fedSnapshot = snapshot;

    final progress = _navigator!.update(position);
    _progress = progress;
    final cues = _announcer!.update(progress, speedMps: snapshot.speedMps);
    if (cues.isNotEmpty && settings.voice) _speak(cues);
    return progress;
  }

  void _speak(List<TurnCue> cues) {
    final l10n = ref.read(navigationLocalizationsProvider);
    final speaker = ref.read(turnSpeakerProvider);
    for (final cue in cues) {
      final phrase = cuePhrase(cue, l10n);
      if (phrase.isNotEmpty) unawaited(speaker.speak(phrase));
    }
  }

  /// Ends a guided ride: the navigator and the announcer go, and anything
  /// still queued in the speaker is dropped.
  void _stop() {
    _forget();
    if (!_guiding) return;
    _guiding = false;
    unawaited(ref.read(turnSpeakerProvider).stop());
  }

  void _forget() {
    _navigator = null;
    _announcer = null;
    _routeKey = null;
    _fedSnapshot = null;
    _progress = null;
  }
}
