/// Test doubles other features may depend on. Nothing in here is imported by
/// production code, but it ships in `lib/` so widget tests outside
/// `features/map` can use it.
library;

export '../domain/map_controller.dart';
export 'fake_compass_source.dart';
export 'fake_map_controller.dart';
