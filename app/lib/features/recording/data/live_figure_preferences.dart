import 'package:flutter/foundation.dart' show immutable, listEquals, setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/app_config.dart';
import '../domain/live_figures.dart';

const String _prefsOrder = 'recording.figureOrder';
const String _prefsDisabled = 'recording.figuresDisabled';

/// Which of a ride's figures show, and in which order.
@immutable
class LiveFigurePreferences {
  /// Creates the preferences.
  const LiveFigurePreferences({required this.order, required this.disabled});

  /// Today's figures in today's order: what a rider who never opened the
  /// list sees.
  static const LiveFigurePreferences defaults = LiveFigurePreferences(
    order: defaultLiveFigureOrder,
    disabled: defaultDisabledLiveFigures,
  );

  /// Every figure, in the rider's order.
  final List<LiveFigure> order;

  /// The ones switched off.
  final Set<LiveFigure> disabled;

  /// The figures that are on, in order: what [liveFigures] is given.
  List<LiveFigure> get shown => <LiveFigure>[
    for (final figure in order)
      if (!disabled.contains(figure)) figure,
  ];

  /// Whether this is the default, so a reset has nothing to do.
  bool get isDefault =>
      listEquals(order, defaults.order) &&
      setEquals(disabled, defaults.disabled);

  @override
  bool operator ==(Object other) =>
      other is LiveFigurePreferences &&
      listEquals(other.order, order) &&
      setEquals(other.disabled, disabled);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(order), Object.hashAllUnordered(disabled));
}

/// Settings → Ride figures, kept in shared_preferences as the search groups
/// are: two string lists of [LiveFigure] names, the order and the ones
/// switched off.
///
/// Read defensively. A name this build does not know is dropped; a figure
/// the stored order does not mention — one added in a later release — goes
/// in at its default place, after the figure it follows by default, and is
/// on or off as it is by default. So a stored order never loses a figure,
/// and a new one appears where a rider who never reordered would see it.
class LiveFigurePreferencesController extends Notifier<LiveFigurePreferences> {
  @override
  LiveFigurePreferences build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return read(prefs);
  }

  /// The preferences stored in [prefs].
  static LiveFigurePreferences read(SharedPreferences prefs) {
    final stored = prefs.getStringList(_prefsOrder);
    final known = <LiveFigure>[
      for (final name in stored ?? const <String>[]) ?LiveFigure.byName(name),
    ];
    final order = <LiveFigure>[];
    for (final figure in known) {
      if (!order.contains(figure)) order.add(figure);
    }
    final missing = <LiveFigure>{};
    for (final (index, figure) in defaultLiveFigureOrder.indexed) {
      if (order.contains(figure)) continue;
      missing.add(figure);
      // After the figure it follows by default, or first when none does.
      var at = 0;
      for (var i = index - 1; i >= 0; i--) {
        final before = order.indexOf(defaultLiveFigureOrder[i]);
        if (before >= 0) {
          at = before + 1;
          break;
        }
      }
      order.insert(at, figure);
    }
    final storedDisabled = prefs.getStringList(_prefsDisabled);
    final disabled = storedDisabled == null
        ? defaultDisabledLiveFigures.toSet()
        : <LiveFigure>{
            for (final name in storedDisabled) ?LiveFigure.byName(name),
          };
    // A figure the stored lists never heard of is as it is by default.
    if (stored != null) {
      for (final figure in missing) {
        if (defaultDisabledLiveFigures.contains(figure)) disabled.add(figure);
      }
    }
    // One figure at least is always on.
    if (disabled.length >= order.length) disabled.remove(order.first);
    return LiveFigurePreferences(order: order, disabled: disabled);
  }

  /// Moves the figure at [oldIndex] so that it sits at [newIndex] afterwards.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final order = state.order.toList();
    if (oldIndex < 0 || oldIndex >= order.length) return;
    final target = newIndex.clamp(0, order.length - 1);
    if (target == oldIndex) return;
    order.insert(target, order.removeAt(oldIndex));
    await _store(LiveFigurePreferences(order: order, disabled: state.disabled));
  }

  /// Switches [figure] on or off; the last one on stays on.
  Future<void> setEnabled(LiveFigure figure, bool enabled) async {
    final disabled = state.disabled.toSet();
    if (enabled) {
      disabled.remove(figure);
    } else {
      disabled.add(figure);
      if (disabled.length >= state.order.length) return;
    }
    await _store(LiveFigurePreferences(order: state.order, disabled: disabled));
  }

  /// Back to today's figures in today's order.
  Future<void> reset() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_prefsOrder);
    await prefs.remove(_prefsDisabled);
    state = LiveFigurePreferences.defaults;
  }

  Future<void> _store(LiveFigurePreferences next) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList(_prefsOrder, <String>[
      for (final figure in next.order) figure.name,
    ]);
    await prefs.setStringList(_prefsDisabled, <String>[
      for (final figure in next.order)
        if (next.disabled.contains(figure)) figure.name,
    ]);
    state = next;
  }
}

/// Which of a ride's figures show, and in which order.
final liveFigurePreferencesProvider =
    NotifierProvider<LiveFigurePreferencesController, LiveFigurePreferences>(
      LiveFigurePreferencesController.new,
    );
