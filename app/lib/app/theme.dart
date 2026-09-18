import 'package:flutter/material.dart';

/// The typeface of headlines and big figures: a condensed grotesk, so a
/// six-digit distance reads at a glance on the handlebar.
const String velorkiDisplayFont = 'BarlowCondensed';

/// The typeface of everything else.
const String velorkiBodyFont = 'Manrope';

/// One accent the rider can pick in Settings → Appearance.
///
/// Each preset carries the vivid accent for dark surfaces, a deeper primary
/// that still reads as text on light surfaces, and the route colour drawn on
/// the map, which has to hold up against both map styles.
enum AccentPreset {
  /// Electric lime: the default, made for the dark map.
  volt(
    dark: Color(0xFFC8F542),
    light: Color(0xFF3F7A00),
    lightContainer: Color(0xFFE3F8A6),
    route: Color(0xFFB4F02E),
    routeOnLight: Color(0xFF4C9A00),
  ),

  /// Coral orange.
  ember(
    dark: Color(0xFFFF7A45),
    light: Color(0xFFC63D12),
    lightContainer: Color(0xFFFFD9CB),
    route: Color(0xFFFF6A2E),
    routeOnLight: Color(0xFFD9420F),
  ),

  /// Ice blue.
  glacier(
    dark: Color(0xFF5CD6FF),
    light: Color(0xFF0071A6),
    lightContainer: Color(0xFFCDEFFF),
    route: Color(0xFF38C6FF),
    routeOnLight: Color(0xFF0082BF),
  ),

  /// Hot pink.
  berry(
    dark: Color(0xFFFF66B0),
    light: Color(0xFFB8155F),
    lightContainer: Color(0xFFFFD4E7),
    route: Color(0xFFFF4FA3),
    routeOnLight: Color(0xFFC81C6B),
  ),

  /// Pine green: the app icon's own colour.
  forest(
    dark: Color(0xFF3FBF8A),
    light: Color(0xFF1B7F5A),
    lightContainer: Color(0xFFC9EFDD),
    route: Color(0xFF22B57C),
    routeOnLight: Color(0xFF1F9468),
  );

  const AccentPreset({
    required this.dark,
    required this.light,
    required this.lightContainer,
    required this.route,
    required this.routeOnLight,
  });

  /// The accent on dark surfaces; dark text sits on it.
  final Color dark;

  /// The accent on light surfaces; white text sits on it.
  final Color light;

  /// The tinted container behind the light accent.
  final Color lightContainer;

  /// The main route line on the dark map.
  final Color route;

  /// The main route line on the light map, deep enough to hold against
  /// pale roads and green parks.
  final Color routeOnLight;

  /// The preset named [name], or [volt] when the name is unknown.
  static AccentPreset fromName(String? name) => AccentPreset.values.firstWhere(
    (preset) => preset.name == name,
    orElse: () => AccentPreset.volt,
  );
}

/// Velorki's own colours, next to the Material scheme: the map layers, the
/// glass surfaces floating over the map, and the semantic colours.
@immutable
class VelorkiColors extends ThemeExtension<VelorkiColors> {
  /// Creates the extension.
  const VelorkiColors({
    required this.accent,
    required this.routeMain,
    required this.routeMainCasing,
    required this.routeAlternative,
    required this.routeAlternatives,
    required this.routePreview,
    required this.track,
    required this.trackSlow,
    required this.trackFast,
    required this.waypointStart,
    required this.waypointEnd,
    required this.waypointVia,
    required this.waypointStroke,
    required this.position,
    required this.success,
    required this.warning,
    required this.glass,
    required this.glassBorder,
    required this.chartFill,
  });

  /// The vivid accent, for figures and indicators.
  final Color accent;

  /// The main route line.
  final Color routeMain;

  /// The darker outline under the main route line.
  final Color routeMainCasing;

  /// Alternative routes, drawn under the main one (the fallback colour).
  final Color routeAlternative;

  /// One colour per alternative, so three variants read apart at a glance.
  final List<Color> routeAlternatives;

  /// A route being previewed or followed.
  final Color routePreview;

  /// The recorded track.
  final Color track;

  /// The slow end of the ride page's speed ramp: a cool blue.
  final Color trackSlow;

  /// The fast end of it, which is the plain track colour.
  final Color trackFast;

  /// Start marker.
  final Color waypointStart;

  /// End marker.
  final Color waypointEnd;

  /// Via markers.
  final Color waypointVia;

  /// The ring around every marker.
  final Color waypointStroke;

  /// The position puck.
  final Color position;

  /// Connected, done, on device.
  final Color success;

  /// Stale, degraded, needs attention.
  final Color warning;

  /// Translucent surface of the panels floating over the map.
  final Color glass;

  /// Hairline around a glass panel.
  final Color glassBorder;

  /// Area fill under the elevation profile.
  final Color chartFill;

  /// `#RRGGBB` for maplibre style properties.
  static String hex(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  @override
  VelorkiColors copyWith({
    Color? accent,
    Color? routeMain,
    Color? routeMainCasing,
    Color? routeAlternative,
    List<Color>? routeAlternatives,
    Color? routePreview,
    Color? track,
    Color? trackSlow,
    Color? trackFast,
    Color? waypointStart,
    Color? waypointEnd,
    Color? waypointVia,
    Color? waypointStroke,
    Color? position,
    Color? success,
    Color? warning,
    Color? glass,
    Color? glassBorder,
    Color? chartFill,
  }) => VelorkiColors(
    accent: accent ?? this.accent,
    routeMain: routeMain ?? this.routeMain,
    routeMainCasing: routeMainCasing ?? this.routeMainCasing,
    routeAlternative: routeAlternative ?? this.routeAlternative,
    routeAlternatives: routeAlternatives ?? this.routeAlternatives,
    routePreview: routePreview ?? this.routePreview,
    track: track ?? this.track,
    trackSlow: trackSlow ?? this.trackSlow,
    trackFast: trackFast ?? this.trackFast,
    waypointStart: waypointStart ?? this.waypointStart,
    waypointEnd: waypointEnd ?? this.waypointEnd,
    waypointVia: waypointVia ?? this.waypointVia,
    waypointStroke: waypointStroke ?? this.waypointStroke,
    position: position ?? this.position,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    glass: glass ?? this.glass,
    glassBorder: glassBorder ?? this.glassBorder,
    chartFill: chartFill ?? this.chartFill,
  );

  @override
  VelorkiColors lerp(ThemeExtension<VelorkiColors>? other, double t) {
    if (other is! VelorkiColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return VelorkiColors(
      accent: mix(accent, other.accent),
      routeMain: mix(routeMain, other.routeMain),
      routeMainCasing: mix(routeMainCasing, other.routeMainCasing),
      routeAlternative: mix(routeAlternative, other.routeAlternative),
      routeAlternatives: <Color>[
        for (var i = 0; i < routeAlternatives.length; i++)
          mix(
            routeAlternatives[i],
            other.routeAlternatives[i % other.routeAlternatives.length],
          ),
      ],
      routePreview: mix(routePreview, other.routePreview),
      track: mix(track, other.track),
      trackSlow: mix(trackSlow, other.trackSlow),
      trackFast: mix(trackFast, other.trackFast),
      waypointStart: mix(waypointStart, other.waypointStart),
      waypointEnd: mix(waypointEnd, other.waypointEnd),
      waypointVia: mix(waypointVia, other.waypointVia),
      waypointStroke: mix(waypointStroke, other.waypointStroke),
      position: mix(position, other.position),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      glass: mix(glass, other.glass),
      glassBorder: mix(glassBorder, other.glassBorder),
      chartFill: mix(chartFill, other.chartFill),
    );
  }
}

/// Shortcut to the extension.
extension VelorkiThemeX on ThemeData {
  /// Velorki's own colours; every theme built here carries them.
  ///
  /// A plain [ThemeData] (a widget test's bare `MaterialApp`) gets the Volt
  /// colours of its brightness, so no widget has to guard the lookup.
  VelorkiColors get velorki =>
      extension<VelorkiColors>() ??
      (brightness == Brightness.dark
          ? _darkColors(AccentPreset.volt, colorScheme)
          : _lightColors(AccentPreset.volt, colorScheme));
}

/// Text styles the Material ramp has no slot for.
extension VelorkiTextX on TextTheme {
  /// A hero figure: distance on the record screen.
  TextStyle get statHero => TextStyle(
    fontFamily: velorkiDisplayFont,
    fontWeight: FontWeight.w700,
    fontSize: 84,
    height: 0.95,
    letterSpacing: -1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// A large figure: the numbers in a stats row.
  TextStyle get statLarge => TextStyle(
    fontFamily: velorkiDisplayFont,
    fontWeight: FontWeight.w700,
    fontSize: 30,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// A figure in a dense grid.
  TextStyle get statMedium => TextStyle(
    fontFamily: velorkiDisplayFont,
    fontWeight: FontWeight.w600,
    fontSize: 24,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// The small upper-case caption above a figure or a section.
  TextStyle get overline => const TextStyle(
    fontFamily: velorkiBodyFont,
    fontWeight: FontWeight.w700,
    fontSize: 11,
    height: 1.2,
    letterSpacing: 1.1,
  );
}

/// The light theme for [preset].
ThemeData buildLightTheme([AccentPreset preset = AccentPreset.volt]) =>
    _build(preset, Brightness.light);

/// The dark theme for [preset].
ThemeData buildDarkTheme([AccentPreset preset = AccentPreset.volt]) =>
    _build(preset, Brightness.dark);

// ------------------------------------------------------------------ palettes

const Color _inkDark = Color(0xFF0E1115);
const Color _inkLight = Color(0xFF14171A);
const Color _paper = Color(0xFFF5F6F3);
const Color _white = Color(0xFFFFFFFF);

ColorScheme _darkScheme(AccentPreset p) => ColorScheme(
  brightness: Brightness.dark,
  primary: p.dark,
  onPrimary: _inkDark,
  primaryContainer: Color.alphaBlend(p.dark.withValues(alpha: 0.22), _inkDark),
  onPrimaryContainer: p.dark,
  secondary: const Color(0xFFC9D1DA),
  onSecondary: _inkDark,
  secondaryContainer: const Color(0xFF2A3037),
  onSecondaryContainer: const Color(0xFFE6EAEE),
  tertiary: const Color(0xFFF0B84A),
  onTertiary: _inkDark,
  tertiaryContainer: const Color(0xFF4A3A12),
  onTertiaryContainer: const Color(0xFFFFE2A8),
  error: const Color(0xFFFF5C6A),
  onError: _inkDark,
  errorContainer: const Color(0xFF4A1A20),
  onErrorContainer: const Color(0xFFFFC9CE),
  surface: const Color(0xFF15181E),
  onSurface: const Color(0xFFF1F3F5),
  onSurfaceVariant: const Color(0xFFAAB2BC),
  surfaceContainerLowest: const Color(0xFF0F1216),
  surfaceContainerLow: const Color(0xFF1B1F26),
  surfaceContainer: const Color(0xFF21262E),
  surfaceContainerHigh: const Color(0xFF2A3039),
  surfaceContainerHighest: const Color(0xFF333A44),
  surfaceDim: const Color(0xFF111418),
  surfaceBright: const Color(0xFF3C444F),
  outline: const Color(0xFF4B535E),
  outlineVariant: const Color(0xFF2C333C),
  inverseSurface: const Color(0xFFF1F3F5),
  onInverseSurface: _inkLight,
  inversePrimary: p.light,
  shadow: Colors.black,
  scrim: Colors.black,
  surfaceTint: Colors.transparent,
);

ColorScheme _lightScheme(AccentPreset p) => ColorScheme(
  brightness: Brightness.light,
  primary: p.light,
  onPrimary: _white,
  primaryContainer: p.lightContainer,
  onPrimaryContainer: Color.alphaBlend(p.light.withValues(alpha: 0.9), _ink),
  secondary: const Color(0xFF3B434C),
  onSecondary: _white,
  secondaryContainer: const Color(0xFFE4E7E2),
  onSecondaryContainer: const Color(0xFF1F252B),
  tertiary: const Color(0xFF9A6A00),
  onTertiary: _white,
  tertiaryContainer: const Color(0xFFFFE3A3),
  onTertiaryContainer: const Color(0xFF3D2A00),
  error: const Color(0xFFC8283A),
  onError: _white,
  errorContainer: const Color(0xFFFFD9DC),
  onErrorContainer: const Color(0xFF5A0F18),
  surface: _paper,
  onSurface: _inkLight,
  onSurfaceVariant: const Color(0xFF5B636C),
  surfaceContainerLowest: _white,
  surfaceContainerLow: const Color(0xFFFBFBF9),
  surfaceContainer: const Color(0xFFEDEFEB),
  surfaceContainerHigh: const Color(0xFFE5E8E2),
  surfaceContainerHighest: const Color(0xFFDDE0DA),
  surfaceDim: const Color(0xFFD9DCD6),
  surfaceBright: _white,
  outline: const Color(0xFFC2C7CC),
  outlineVariant: const Color(0xFFE0E3DF),
  inverseSurface: _inkLight,
  onInverseSurface: _paper,
  inversePrimary: p.dark,
  shadow: Colors.black,
  scrim: Colors.black,
  surfaceTint: Colors.transparent,
);

const Color _ink = _inkLight;

VelorkiColors _darkColors(AccentPreset p, ColorScheme scheme) => VelorkiColors(
  accent: p.dark,
  routeMain: p.route,
  routeMainCasing: _inkDark,
  routeAlternative: const Color(0xFF7C8794),
  routeAlternatives: const <Color>[
    Color(0xFF6AA0FF),
    Color(0xFFB48CFF),
    Color(0xFF3ED1C4),
  ],
  routePreview: const Color(0xFFF0B84A),
  track: p.dark,
  trackSlow: const Color(0xFF58A6FF),
  trackFast: p.dark,
  waypointStart: const Color(0xFF3DDC84),
  waypointEnd: const Color(0xFFFF4D6A),
  waypointVia: _white,
  waypointStroke: _inkDark,
  position: const Color(0xFF4DA3FF),
  success: const Color(0xFF3DDC84),
  warning: const Color(0xFFF0B84A),
  glass: const Color(0xEB1B1F26),
  glassBorder: const Color(0x2EFFFFFF),
  chartFill: p.dark.withValues(alpha: 0.18),
);

VelorkiColors _lightColors(AccentPreset p, ColorScheme scheme) => VelorkiColors(
  accent: p.light,
  // The deep variant: the bright one washes out on pale roads and parks.
  routeMain: p.routeOnLight,
  routeMainCasing: _inkLight,
  routeAlternative: const Color(0xFF8A939E),
  routeAlternatives: const <Color>[
    Color(0xFF3F6FD8),
    Color(0xFF8E4BD8),
    Color(0xFF0E9B8F),
  ],
  routePreview: const Color(0xFFE08A00),
  track: p.routeOnLight,
  trackSlow: const Color(0xFF1D6FD0),
  trackFast: p.routeOnLight,
  waypointStart: const Color(0xFF1FA85F),
  waypointEnd: const Color(0xFFE0304C),
  waypointVia: _white,
  waypointStroke: _inkLight,
  position: const Color(0xFF1E7CE6),
  success: const Color(0xFF1FA85F),
  warning: const Color(0xFFC77800),
  glass: const Color(0xF0FFFFFF),
  glassBorder: const Color(0x1F000000),
  chartFill: p.light.withValues(alpha: 0.14),
);

// -------------------------------------------------------------------- build

ThemeData _build(AccentPreset preset, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _darkScheme(preset) : _lightScheme(preset);
  final colors = dark
      ? _darkColors(preset, scheme)
      : _lightColors(preset, scheme);
  final text = _textTheme(scheme);
  const pill = StadiumBorder();
  final buttonText = text.labelLarge!.copyWith(fontWeight: FontWeight.w700);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    fontFamily: velorkiBodyFont,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    extensions: <ThemeExtension<dynamic>>[colors],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        textStyle: buttonText,
        side: BorderSide(color: scheme.outline),
        foregroundColor: scheme.onSurface,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: pill,
        minimumSize: const Size(48, 44),
        textStyle: buttonText,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: pill,
        minimumSize: const Size(64, 52),
        textStyle: buttonText,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: const CircleBorder()),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: pill,
        textStyle: text.labelLarge,
        selectedBackgroundColor: scheme.primary,
        selectedForegroundColor: scheme.onPrimary,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.primary,
      // Material 3 chips read `color` first; without it a ChoiceChip falls
      // back to its own translucent defaults over the map.
      color: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerLow,
      ),
      secondarySelectedColor: scheme.primary,
      checkmarkColor: scheme.onPrimary,
      showCheckmark: false,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      // ChoiceChip resolves the label *colour* per state, not the whole
      // style, so the state-aware part has to be the colour itself.
      labelStyle: text.labelLarge!.copyWith(
        fontWeight: FontWeight.w700,
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurface,
        ),
      ),
      iconTheme: IconThemeData(
        size: 18,
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurface,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: scheme.surface,
      showDragHandle: true,
      dragHandleColor: scheme.outline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      actionTextColor: dark ? preset.light : preset.dark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.titleMedium,
      subtitleTextStyle: text.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      iconColor: scheme.onSurfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHigh,
      circularTrackColor: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHigh,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHigh,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(textStyle: text.bodyLarge),
  );
}

TextTheme _textTheme(ColorScheme scheme) {
  TextStyle display(double size, {double spacing = -0.5}) => TextStyle(
    fontFamily: velorkiDisplayFont,
    fontWeight: FontWeight.w700,
    fontSize: size,
    height: 1,
    letterSpacing: spacing,
    color: scheme.onSurface,
  );
  TextStyle body(
    double size,
    FontWeight weight, {
    double height = 1.4,
    double spacing = 0,
    Color? color,
  }) => TextStyle(
    fontFamily: velorkiBodyFont,
    fontWeight: weight,
    fontSize: size,
    height: height,
    letterSpacing: spacing,
    color: color ?? scheme.onSurface,
  );
  return TextTheme(
    displayLarge: display(64),
    displayMedium: display(52),
    displaySmall: display(44),
    headlineLarge: display(36, spacing: -0.25),
    headlineMedium: display(30, spacing: -0.25),
    headlineSmall: display(26, spacing: 0),
    titleLarge: body(21, FontWeight.w700, height: 1.25, spacing: -0.3),
    titleMedium: body(16, FontWeight.w700, height: 1.3, spacing: -0.1),
    titleSmall: body(14, FontWeight.w700, height: 1.3),
    bodyLarge: body(16, FontWeight.w500, height: 1.45),
    bodyMedium: body(14, FontWeight.w500, height: 1.45),
    bodySmall: body(
      12,
      FontWeight.w500,
      height: 1.4,
      color: scheme.onSurfaceVariant,
    ),
    labelLarge: body(14, FontWeight.w600, height: 1.2, spacing: 0.1),
    labelMedium: body(12, FontWeight.w600, height: 1.2, spacing: 0.3),
    labelSmall: body(
      11,
      FontWeight.w600,
      height: 1.2,
      spacing: 0.4,
      color: scheme.onSurfaceVariant,
    ),
  );
}
