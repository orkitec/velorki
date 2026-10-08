import 'dart:async';

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'system_power_save.g.dart';

/// Asks the platform whether the phone is saving power: Low Power Mode on
/// iOS, Battery Saver on Android.
///
/// Mirrored in `ios/Runner/AppDelegate.swift` and
/// `android/.../MainActivity.kt`: `isOn` answers a bool, and the platform
/// calls `changed` with the new bool whenever the mode is switched.
class PowerSaveChannel {
  /// Creates the channel wrapper; [channel] is only replaced by tests.
  PowerSaveChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// The channel's name.
  static const String channelName = 'velorki/power_save';

  final MethodChannel _channel;

  /// Whether the phone saves power now; false when the platform cannot say.
  Future<bool> current() async {
    try {
      return await _channel.invokeMethod<bool>('isOn') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Calls [onChanged] whenever the platform reports a switch.
  void listen(void Function(bool on) onChanged) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') onChanged(call.arguments == true);
    });
  }

  /// Stops listening.
  void close() => _channel.setMethodCallHandler(null);
}

/// The channel the power-saving mode is read through; tests replace it.
@Riverpod(keepAlive: true)
PowerSaveChannel powerSaveChannel(Ref ref) => PowerSaveChannel();

/// Whether the phone's own power-saving mode is on, live; false wherever
/// the platform cannot say.
@Riverpod(keepAlive: true)
Stream<bool> systemPowerSave(Ref ref) {
  final channel = ref.watch(powerSaveChannelProvider);
  final controller = StreamController<bool>();
  var heard = false;
  channel.listen((on) {
    heard = true;
    controller.add(on);
  });
  unawaited(
    channel.current().then((on) {
      // A switch reported while the question was out is newer.
      if (!heard && !controller.isClosed) controller.add(on);
    }),
  );
  ref.onDispose(() {
    channel.close();
    unawaited(controller.close());
  });
  return controller.stream;
}
