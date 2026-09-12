import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// Strava's official "Connect with Strava" button, orange variant.
const String stravaConnectButtonOrange =
    'assets/strava/btn_strava_connect_with_orange.png';

/// The same button in white, for dark backgrounds.
const String stravaConnectButtonWhite =
    'assets/strava/btn_strava_connect_with_white.png';

/// The horizontal "Powered by Strava" logo, orange variant.
const String stravaPoweredByOrange =
    'assets/strava/api_logo_pwrdBy_strava_horiz_orange.png';

/// The same logo in white, for dark backgrounds.
const String stravaPoweredByWhite =
    'assets/strava/api_logo_pwrdBy_strava_horiz_white.png';

/// The height Strava's brand guidelines give the connect button, and the
/// height of the shipped 1x asset.
const double stravaConnectButtonHeight = 48;

/// The height the "Powered by Strava" logo is drawn at.
const double stravaPoweredByHeight = 24;

/// Strava's official connect button, used unmodified.
///
/// The brand guidelines require this exact artwork and the wording "Connect
/// with Strava"; the app may not draw its own. [label] is only the
/// accessibility label and the fallback for a build whose assets are missing
/// — a fork that strips `assets/strava/` still gets a working button rather
/// than a broken image.
class StravaConnectButton extends StatelessWidget {
  /// Creates the button. A null [onPressed] dims it and makes it inert.
  const StravaConnectButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// "Connect with Strava", from the ARB.
  final String label;

  /// What a tap does, or null when the rider may not connect yet.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            dark ? stravaConnectButtonWhite : stravaConnectButtonOrange,
            height: stravaConnectButtonHeight,
            errorBuilder: (context, _, _) =>
                FilledButton.tonal(onPressed: onPressed, child: Text(label)),
          ),
        ),
      ),
    );
  }
}

/// Strava's "Powered by Strava" logo.
///
/// Their API terms require it on every surface that shows data coming from
/// Strava, which in Velorki is the list of imported Strava routes.
class PoweredByStrava extends StatelessWidget {
  /// Creates the logo.
  const PoweredByStrava({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark ? stravaPoweredByWhite : stravaPoweredByOrange,
      height: stravaPoweredByHeight,
      semanticLabel: l10n.poweredByStrava,
      errorBuilder: (context, _, _) => Text(
        l10n.poweredByStrava,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
