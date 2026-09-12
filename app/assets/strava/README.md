# Strava brand assets

These are Strava's official API brand assets, used unmodified. They are
**not** covered by the app's Apache-2.0 licence: they are Strava's trademarks,
licensed to API applications through the
[Strava brand guidelines](https://developers.strava.com/guidelines/). A fork
that is not a registered Strava API application must remove this directory.

## What is here, and where it came from

Downloaded on 12 September 2026 from the "Brand assets" links on
<https://developers.strava.com/guidelines/>:

| Source | File in the kit | Here |
|---|---|---|
| [1.1-Connect-with-Strava-Buttons.zip](https://developers.strava.com/downloads/1.1-Connect-with-Strava-Buttons.zip) | `Connect with Strava Orange/btn_strava_connect_with_orange.png` (237×48) | `btn_strava_connect_with_orange.png` |
| ″ | `…_orange_x2.png` (474×96) | `2.0x/btn_strava_connect_with_orange.png` |
| ″ | `Connect with Strava White/btn_strava_connect_with_white.png` (237×48) | `btn_strava_connect_with_white.png` |
| ″ | `…_white_x2.png` (474×96) | `2.0x/btn_strava_connect_with_white.png` |
| [1.2-Strava-API-Logos.zip](https://developers.strava.com/downloads/1.2-Strava-API-Logos.zip) | `Powered by Strava/pwrdBy_strava_orange/api_logo_pwrdBy_strava_horiz_orange.svg` | `api_logo_pwrdBy_strava_horiz_orange.png` and its `2.0x`/`3.0x` variants |
| ″ | `…/pwrdBy_strava_white/api_logo_pwrdBy_strava_horiz_white.svg` | `api_logo_pwrdBy_strava_horiz_white.png` and its `2.0x`/`3.0x` variants |

The connect buttons are the kit's PNGs byte for byte. The "Powered by Strava"
logos were rasterised from the kit's SVGs at 24, 48 and 72 pixels high
(`rsvg-convert -h 24 …`), because the kit ships only one raster size; nothing
but the scale was changed, and the aspect ratio is the original 365 : 37.

## Rules that the code follows

* The connect button is drawn at its natural **48 logical pixels high** and is
  never recoloured, re-typeset, cropped or padded (`StravaConnectButton` in
  `lib/features/integrations/presentation/strava_brand.dart`).
* The orange button is used on light backgrounds, the white one on dark.
* The wording is "Connect with Strava", verbatim, and is the button's
  accessibility label.
* "Powered by Strava" appears on every screen that shows data coming from
  Strava — currently the imported-routes list.
* Every Strava activity the app links to opens as "View on Strava".
* "Strava" is not part of the app name, the store title or the app icon.

## Replacing or removing them

The widgets fall back to a plain text button and a text credit when an asset
is missing (`Image.asset(..., errorBuilder:)`), so a fork can delete the PNGs
and still build. To refresh them, download the two ZIPs above and repeat the
table; keep the file names, they are what `pubspec.yaml` declares.
