/// Client and models for the Velorki relay API.
///
/// Pure Dart: no Flutter, no `dart:io`, no code generation. See README.md.
library;

export 'src/errors.dart'
    show
        RelayError,
        RelayErrorCode,
        RelayException,
        RelayFormatException,
        decodeJsonObject;
export 'src/models.dart';
export 'src/plan_events.dart';
export 'src/relay_client.dart';
export 'src/sse.dart';
export 'src/version.dart';
