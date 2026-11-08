// The watch link over `watch_connectivity`, the plugin the F-Droid build
// leaves out. Which gateway each build gets is pinned in
// test/app/proprietary_services_test.dart; this is the real one's behaviour.
//
// The point of nearly every test here is the same: a phone with no watch, or
// a plugin that is not there at all, must answer "no" rather than throw. The
// caller is a ride that is recording.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:velorki/features/sensors/data/plugin_watch_gateway.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

class _MockWatch extends Mock implements WatchConnectivity {}

/// Mirrored in `ios/Runner/AppDelegate.swift`.
const MethodChannel _native = MethodChannel('velorki/watch');

/// Answers the native channel with [answers], or throws what it holds.
List<MethodCall> _mockNative(Map<String, Object?> answers) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_native, (call) async {
        calls.add(call);
        final answer = answers[call.method];
        if (answer is PlatformException) throw answer;
        return answer;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native, null),
  );
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockWatch watch;
  late PluginWatchGateway gateway;

  setUp(() {
    watch = _MockWatch();
    gateway = PluginWatchGateway(watch: watch);
  });

  group('asking the plugin about the watch', () {
    test('passes on what it says', () async {
      when(() => watch.isSupported).thenAnswer((_) async => true);
      when(() => watch.isPaired).thenAnswer((_) async => true);
      when(() => watch.isReachable).thenAnswer((_) async => false);

      expect(await gateway.isSupported(), isTrue);
      expect(await gateway.isPaired(), isTrue);
      expect(await gateway.isReachable(), isFalse);
    });

    test('and answers no when it throws, rather than into the ride', () async {
      when(() => watch.isSupported).thenThrow(MissingPluginException());
      when(() => watch.isPaired).thenThrow(Exception('no watch'));
      when(() => watch.isReachable).thenThrow(Exception('no watch'));

      expect(await gateway.isSupported(), isFalse);
      expect(await gateway.isPaired(), isFalse);
      expect(await gateway.isReachable(), isFalse);
    });
  });

  group('sending to the watch', () {
    test('a message goes as it is', () async {
      when(() => watch.sendMessage(any())).thenAnswer((_) async {});
      await gateway.sendMessage({'kind': 'tick', 'distance': 1200});
      verify(() => watch.sendMessage({'kind': 'tick', 'distance': 1200}))
          .called(1);
    });

    test('and a failed send is swallowed', () async {
      when(() => watch.sendMessage(any())).thenThrow(Exception('unreachable'));
      await expectLater(gateway.sendMessage(const {'kind': 'tick'}), completes);
    });

    test('the application context likewise', () async {
      when(() => watch.updateApplicationContext(any()))
          .thenAnswer((_) async {});
      await gateway.updateApplicationContext(const {'recording': true});
      verify(() => watch.updateApplicationContext({'recording': true}))
          .called(1);

      when(() => watch.updateApplicationContext(any()))
          .thenThrow(Exception('no watch'));
      await expectLater(
        gateway.updateApplicationContext(const {'recording': false}),
        completes,
      );
    });
  });

  test('the messages the watch sends come through, and an error on the '
      'stream does not close the ride\'s listener', () async {
    final sent = StreamController<Map<String, dynamic>>();
    addTearDown(sent.close);
    when(() => watch.messageStream).thenAnswer((_) => sent.stream);

    final seen = <Map<String, Object?>>[];
    final sub = gateway.messages.listen(seen.add);
    addTearDown(sub.cancel);

    sent.add({'kind': 'heartRate', 'bpm': 142});
    sent.addError(Exception('watch went away'));
    sent.add({'kind': 'heartRate', 'bpm': 141});
    await Future<void>.delayed(Duration.zero);

    expect(seen, [
      {'kind': 'heartRate', 'bpm': 142},
      {'kind': 'heartRate', 'bpm': 141},
    ]);
  });

  group('the native channel beside the plugin', () {
    test('launching a workout on the watch', () async {
      final calls = _mockNative({'launchWorkout': true});
      expect(await gateway.launchWorkout(), isTrue);
      expect(calls.single.method, 'launchWorkout');
    });

    test('a watch that would not start one', () async {
      _mockNative({'launchWorkout': false});
      expect(await gateway.launchWorkout(), isFalse);
    });

    test(
      'and no iOS side at all — Android, where the method is not there',
      () async {
        // No handler registered: the channel throws MissingPluginException.
        expect(await gateway.launchWorkout(), isFalse);
        expect(
          await gateway.notifyRideStarted(
            title: 'Riding',
            body: 'From a watch',
          ),
          isFalse,
        );
      },
    );

    test(
      'the notice that the watch started a ride carries its words',
      () async {
        final calls = _mockNative({'notifyRideStarted': true});
        expect(
          await gateway.notifyRideStarted(
            title: 'Riding',
            body: 'From a watch',
          ),
          isTrue,
        );
        expect(calls.single.method, 'notifyRideStarted');
        expect(calls.single.arguments, {
          'title': 'Riding',
          'body': 'From a watch',
        });
      },
    );

    test('a platform error is no reason to interrupt anything', () async {
      _mockNative({
        'launchWorkout': PlatformException(code: 'no_watch'),
        'notifyRideStarted': PlatformException(code: 'denied'),
      });
      expect(await gateway.launchWorkout(), isFalse);
      expect(await gateway.notifyRideStarted(title: 't', body: 'b'), isFalse);
    });
  });
}
