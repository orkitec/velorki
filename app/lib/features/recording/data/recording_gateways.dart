import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// The notification permission the Android foreground service needs.
///
/// Behind an interface because every widget test would otherwise talk to a
/// platform channel that is not there.
abstract interface class NotificationPermissionGateway {
  /// Whether notifications may be posted.
  Future<bool> isGranted();

  /// Shows the system prompt when that can still do something.
  Future<bool> request();
}

/// [NotificationPermissionGateway] over flutter_foreground_task, which asks
/// the platform directly instead of pulling in a second permission plugin.
class ForegroundTaskNotificationPermission
    implements NotificationPermissionGateway {
  /// Creates the gateway.
  const ForegroundTaskNotificationPermission();

  @override
  Future<bool> isGranted() async =>
      await FlutterForegroundTask.checkNotificationPermission() ==
      NotificationPermission.granted;

  @override
  Future<bool> request() async =>
      await FlutterForegroundTask.requestNotificationPermission() ==
      NotificationPermission.granted;
}

/// The battery-optimisation exemption, asked for once with an explanation.
///
/// Without it some manufacturers' aggressive task killers stop the service
/// after a while, which is exactly the hour-long ride the rider cares about.
abstract interface class BatteryOptimizationGateway {
  /// Whether the app is already exempt — always `true` off Android.
  Future<bool> isIgnored();

  /// Opens the system prompt.
  Future<bool> request();
}

/// [BatteryOptimizationGateway] over flutter_foreground_task.
class ForegroundTaskBatteryOptimization implements BatteryOptimizationGateway {
  /// Creates the gateway.
  const ForegroundTaskBatteryOptimization();

  @override
  Future<bool> isIgnored() async =>
      defaultTargetPlatform != TargetPlatform.android ||
      await FlutterForegroundTask.isIgnoringBatteryOptimizations;

  @override
  Future<bool> request() =>
      FlutterForegroundTask.requestIgnoreBatteryOptimization();
}

/// Keeping the display awake while the recording screen is open.
///
/// This is only about the screen: the CPU wake lock that keeps the recording
/// alive belongs to the foreground service's task options.
abstract interface class ScreenWake {
  /// Prevents the display from switching off.
  Future<void> enable();

  /// Lets the display switch off again.
  Future<void> disable();
}

/// [ScreenWake] over wakelock_plus.
class WakelockScreenWake implements ScreenWake {
  /// Creates the gateway.
  const WakelockScreenWake();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

/// The notification permission gateway.
final notificationPermissionProvider = Provider<NotificationPermissionGateway>(
  (ref) => const ForegroundTaskNotificationPermission(),
);

/// The battery-optimisation gateway.
final batteryOptimizationProvider = Provider<BatteryOptimizationGateway>(
  (ref) => const ForegroundTaskBatteryOptimization(),
);

/// The keep-screen-on gateway.
final screenWakeProvider = Provider<ScreenWake>(
  (ref) => const WakelockScreenWake(),
);
