import 'package:flutter_test/flutter_test.dart';
import 'package:live_activities/live_activities.dart';
import 'package:mocktail/mocktail.dart';
import 'package:velorki/features/recording/data/live_activity.dart';

class _MockLiveActivities extends Mock implements LiveActivities {}

void main() {
  late _MockLiveActivities plugin;
  late PluginRideLiveActivity activity;

  setUp(() {
    plugin = _MockLiveActivities();
    activity = PluginRideLiveActivity(plugin: plugin);
    when(
      () => plugin.init(
        appGroupId: any(named: 'appGroupId'),
        requestAndroidNotificationPermission: any(
          named: 'requestAndroidNotificationPermission',
        ),
      ),
    ).thenAnswer((_) async {});
    when(() => plugin.areActivitiesSupported()).thenAnswer((_) async => true);
    when(() => plugin.updateActivity(any(), any())).thenAnswer((_) async {});
    when(() => plugin.endActivity(any())).thenAnswer((_) async {});
  });

  test('updates and ends the activity under the id ActivityKit handed '
      'back, not the name it was requested under', () async {
    when(
      () => plugin.createActivity(
        any(),
        any(),
        iOSEnableRemoteUpdates: any(named: 'iOSEnableRemoteUpdates'),
        removeWhenAppIsKilled: any(named: 'removeWhenAppIsKilled'),
      ),
    ).thenAnswer((_) async => 'A1B2');

    await activity.start({'distance': '0 m'});
    await activity.update({'distance': '120 m'});
    await activity.end();

    verify(() => plugin.updateActivity('A1B2', {'distance': '120 m'}))
        .called(1);
    verify(() => plugin.endActivity('A1B2')).called(1);
    verifyNever(() => plugin.updateActivity(rideActivityId, any()));
  });

  test('without an activity, updates and end do nothing', () async {
    when(
      () => plugin.createActivity(
        any(),
        any(),
        iOSEnableRemoteUpdates: any(named: 'iOSEnableRemoteUpdates'),
        removeWhenAppIsKilled: any(named: 'removeWhenAppIsKilled'),
      ),
    ).thenThrow(Exception('no ActivityKit here'));

    await activity.start({'distance': '0 m'});
    await activity.update({'distance': '120 m'});
    await activity.end();

    verifyNever(() => plugin.updateActivity(any(), any()));
    verifyNever(() => plugin.endActivity(any()));
  });

  test('a second start while one runs is ignored', () async {
    when(
      () => plugin.createActivity(
        any(),
        any(),
        iOSEnableRemoteUpdates: any(named: 'iOSEnableRemoteUpdates'),
        removeWhenAppIsKilled: any(named: 'removeWhenAppIsKilled'),
      ),
    ).thenAnswer((_) async => 'A1B2');

    await activity.start({});
    await activity.start({});

    verify(
      () => plugin.createActivity(
        any(),
        any(),
        iOSEnableRemoteUpdates: any(named: 'iOSEnableRemoteUpdates'),
        removeWhenAppIsKilled: any(named: 'removeWhenAppIsKilled'),
      ),
    ).called(1);
  });
}
