import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/shell_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(ScreenSideChannel.channelName);

  /// Answers `side` with whatever [answer] holds at the time, and counts
  /// the questions.
  var asked = 0;
  Object? answer;
  setUp(() {
    debugShellLayoutOverride = null;
    asked = 0;
    answer = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'side') return null;
      asked++;
      return answer;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> turn(Object? side) async {
    answer = side;
    await messenger.handlePlatformMessage(
      ScreenSideChannel.channelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('sideChanged', side),
      ),
      (_) {},
    );
  }

  group('ShellLayout.resolve', () {
    test('an upright screen keeps the bar at the bottom', () {
      expect(
        ShellLayout.resolve(const Size(402, 874), RailSide.left),
        ShellLayout.bottomBar,
      );
    });

    test('a screen on its side puts the rail where the bottom went', () {
      final layout = ShellLayout.resolve(const Size(874, 402), RailSide.left);
      expect(layout.sideRail, isTrue);
      expect(layout.side, RailSide.left);
    });

    test('upright, the remembered side makes no difference', () {
      expect(
        const ShellLayout(sideRail: false, side: RailSide.left),
        const ShellLayout(sideRail: false),
      );
      expect(
        const ShellLayout(sideRail: true, side: RailSide.left),
        isNot(const ShellLayout(sideRail: true)),
      );
    });

    test('a square screen counts as upright', () {
      expect(
        ShellLayout.resolve(const Size(500, 500), RailSide.right).sideRail,
        isFalse,
      );
    });
  });

  group('ShellLayout.resolve by the window alone', () {
    ShellLayout resolve(Size window) =>
        ShellLayout.resolve(window, RailSide.left);

    test('a tablet-class window gets the panel, either way up', () {
      for (final window in const [
        // iPad Air 11", iPad Pro 13", iPad mini.
        Size(820, 1180),
        Size(1032, 1376),
        Size(744, 1133),
        // A foldable's inner screen, and half of an iPad's.
        Size(626, 890),
        Size(669, 951),
        Size(683, 1024),
        Size(600, 1000),
      ]) {
        expect(resolve(window), ShellLayout.wide, reason: '$window');
        expect(resolve(window.flipped), ShellLayout.wide, reason: '$window');
      }
    });

    test('a narrow window is upright, the bar at the bottom', () {
      for (final window in const [
        // A third of Split View, Slide Over, a foldable's outer screen.
        Size(507, 1180),
        Size(320, 1100),
        Size(466, 678),
        // As tall as a tablet, not wide enough beside the panel.
        Size(599, 1180),
        Size(402, 874),
      ]) {
        expect(resolve(window), ShellLayout.bottomBar, reason: '$window');
      }
    });

    test('a window shaped like a phone on its side gets the rail, whatever '
        'it runs on', () {
      for (final window in const [
        Size(874, 402),
        Size(956, 440),
        Size(667, 375),
        // A foldable's outer screen sideways, a short Stage Manager window.
        Size(678, 466),
        Size(800, 500),
      ]) {
        final layout = resolve(window);
        expect(layout.sideRail, isTrue, reason: '$window');
        expect(layout.side, RailSide.left);
      }
    });

    test('the wide layout is neither the bar\'s nor the rail\'s', () {
      expect(ShellLayout.wide.widePanel, isTrue);
      expect(ShellLayout.wide.sideRail, isFalse);
      expect(ShellLayout.wide, isNot(ShellLayout.bottomBar));
      expect(ShellLayout.bottomBar.widePanel, isFalse);
    });
  });

  test('the platform answer is read as a side, anything else as none', () {
    expect(ScreenSideChannel.parse('left'), RailSide.left);
    expect(ScreenSideChannel.parse('right'), RailSide.right);
    expect(ScreenSideChannel.parse(null), isNull);
    expect(ScreenSideChannel.parse('up'), isNull);
  });

  group('railSideProvider', () {
    test('starts on the right and takes what the platform says', () async {
      answer = 'left';
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(railSideProvider), RailSide.right);
      await pumpEventQueue();
      expect(container.read(railSideProvider), RailSide.left);
    });

    test('follows a turn the platform reports', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(railSideProvider);
      await pumpEventQueue();
      await turn('left');
      expect(container.read(railSideProvider), RailSide.left);
      await turn('right');
      expect(container.read(railSideProvider), RailSide.right);
    });

    test('keeps its side when the screen turns upright', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(railSideProvider);
      await turn('left');
      await turn(null);
      expect(container.read(railSideProvider), RailSide.left);
    });

    test('stays on the right without a platform to ask', () async {
      messenger.setMockMethodCallHandler(channel, null);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(railSideProvider);
      await pumpEventQueue();
      expect(container.read(railSideProvider), RailSide.right);
    });
  });

  group('ShellLayoutHost', () {
    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
    }

    ShellLayout? seen;
    Widget host() => ProviderScope(
      child: ShellLayoutHost(
        builder: (context, layout) {
          seen = ShellLayout.of(context);
          expect(layout, seen);
          return const SizedBox.shrink();
        },
      ),
    );

    testWidgets('hands down the layout for the screen it is on', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      answer = 'left';
      await pumpAt(tester, const Size(402, 874));
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(seen, ShellLayout.bottomBar);

      await pumpAt(tester, const Size(874, 402));
      expect(seen, const ShellLayout(sideRail: true, side: RailSide.left));
    });

    testWidgets('asks the platform again when the screen turns', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      await pumpAt(tester, const Size(402, 874));
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final before = asked;

      answer = 'left';
      await pumpAt(tester, const Size(874, 402));
      expect(asked, greaterThan(before));
      expect(seen?.side, RailSide.left);
    });
  });

  testWidgets('without a shell a screen reads the layout off its own size', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(874, 402);
    tester.view.devicePixelRatio = 1;
    ShellLayout? seen;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = ShellLayout.of(context);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(seen, const ShellLayout(sideRail: true));
  });
}
