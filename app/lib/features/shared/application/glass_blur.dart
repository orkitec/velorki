import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'glass_blur.g.dart';

/// Whether the glass can blur the map behind it here.
///
/// On the phone it always can. In a browser the map is blurred by the
/// browser's own `backdrop-filter` (`app/web/web_glass_layer.dart`), which
/// the browser's bootstrap checks for; where it is missing, the rider asked
/// for less transparency, or it makes the map too slow, this turns false,
/// and the glass styles are drawn as Subtle: tinted, the map unblurred
/// ([shownBarStyle]).
@Riverpod(keepAlive: true)
class GlassBlur extends _$GlassBlur {
  @override
  bool build() => true;

  /// The browser cannot blur the map, for good.
  void unavailable() => state = false;
}

/// Whether a browser blurs the map behind the glass: it has to have
/// `backdrop-filter`, the rider must not have asked for less transparency,
/// and the blur must not have made the map too slow ([framesTooSlow]).
bool browserBlursGlass({
  required bool backdropFilter,
  required bool reducedTransparency,
  required bool tooSlow,
}) => backdropFilter && !reducedTransparency && !tooSlow;

/// How many frame intervals [framesTooSlow] looks at.
const int glassFrameWindow = 90;

/// The median frame interval, in milliseconds, above which the blur counts
/// as too slow: under 30 frames a second while the glass is on screen.
const double glassSlowFrameMs = 34;

/// Whether the last [glassFrameWindow] frame intervals [intervalsMs], taken
/// while the map moved under the glass, say the blur costs too much: their
/// median over [glassSlowFrameMs]. Fewer intervals than that say nothing
/// yet, and a long pause (the page in the background) is not a slow frame.
bool framesTooSlow(List<double> intervalsMs) {
  final recent = <double>[
    for (final ms in intervalsMs.reversed.take(glassFrameWindow))
      if (ms < 250) ms,
  ];
  if (recent.length < glassFrameWindow * 2 ~/ 3) return false;
  recent.sort();
  return recent[recent.length ~/ 2] > glassSlowFrameMs;
}
