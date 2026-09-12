/// Garmin FIT activity and course files for Velorki.
///
/// Decodes FIT activities into `velorki_geo` track points and encodes track
/// points back into FIT activity and course files. Pure Dart, no Flutter
/// dependency. See README.md.
library;

export 'src/fit_codec.dart'
    show
        FitCodec,
        degreesPerSemicircle,
        fitEpochOffsetSeconds,
        semicirclesPerDegree;
export 'src/fit_format_exception.dart';
export 'src/fit_sniffer.dart';
export 'src/fit_sport.dart';
export 'src/version.dart';
