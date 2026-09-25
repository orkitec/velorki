import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/data/live_figure_preferences.dart';
import 'package:velorki/features/recording/domain/live_figures.dart';

Future<ProviderContainer> _container(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'nothing stored: today\'s figures in today\'s order, elapsed off',
    () async {
      final c = await _container(const {});
      final p = c.read(liveFigurePreferencesProvider);
      expect(p.order, defaultLiveFigureOrder);
      expect(p.shown, defaultShownLiveFigures);
      expect(p.isDefault, isTrue);
    },
  );

  test('a stored order and switches are read back', () async {
    final c = await _container(const {
      'recording.figureOrder': [
        'speed',
        'distance',
        'avgSpeed',
        'ascent',
        'descent',
        'movingTime',
        'heartRate',
        'cadence',
        'power',
        'remaining',
        'arrival',
        'elapsed',
      ],
      'recording.figuresDisabled': ['ascent'],
    });
    final p = c.read(liveFigurePreferencesProvider);
    expect(p.shown.take(3), [
      LiveFigure.speed,
      LiveFigure.distance,
      LiveFigure.avgSpeed,
    ]);
    expect(p.shown, isNot(contains(LiveFigure.ascent)));
    expect(p.shown, contains(LiveFigure.elapsed));
  });

  test('an older order that lacks figures gets them at their default place, '
      'as they are by default, and drops names it does not know', () async {
    final c = await _container(const {
      // Saved before cadence, power and elapsed existed, with a name from a
      // later release this build does not know.
      'recording.figureOrder': [
        'movingTime',
        'distance',
        'speed',
        'avgSpeed',
        'ascent',
        'descent',
        'heartRate',
        'gradient',
        'remaining',
        'arrival',
      ],
      'recording.figuresDisabled': <String>[],
    });
    final p = c.read(liveFigurePreferencesProvider);
    expect(p.order, [
      LiveFigure.movingTime,
      LiveFigure.distance,
      LiveFigure.speed,
      LiveFigure.avgSpeed,
      LiveFigure.ascent,
      LiveFigure.descent,
      LiveFigure.heartRate,
      LiveFigure.cadence,
      LiveFigure.power,
      LiveFigure.remaining,
      LiveFigure.arrival,
      LiveFigure.elapsed,
    ]);
    expect(p.disabled, {LiveFigure.elapsed});
  });

  test('reorder and switch are stored; the last figure on stays on; reset '
      'forgets both', () async {
    final c = await _container(const {});
    final controller = c.read(liveFigurePreferencesProvider.notifier);
    await controller.reorder(5, 0);
    await controller.setEnabled(LiveFigure.speed, false);
    var p = c.read(liveFigurePreferencesProvider);
    expect(p.shown.first, LiveFigure.movingTime);
    expect(p.shown, isNot(contains(LiveFigure.speed)));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('recording.figureOrder')!.first, 'movingTime');
    expect(prefs.getStringList('recording.figuresDisabled'), [
      'speed',
      'elapsed',
    ]);
    // Read back fresh, as the next launch does.
    expect(LiveFigurePreferencesController.read(prefs), p);

    for (final figure in LiveFigure.values) {
      await controller.setEnabled(figure, false);
    }
    p = c.read(liveFigurePreferencesProvider);
    expect(p.shown, hasLength(1));

    await controller.reset();
    expect(c.read(liveFigurePreferencesProvider).isDefault, isTrue);
    expect(prefs.getStringList('recording.figureOrder'), isNull);
    expect(prefs.getStringList('recording.figuresDisabled'), isNull);
  });
}
