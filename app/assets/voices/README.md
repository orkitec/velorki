# Voice catalogue

`catalogue.json` says what the phone's text-to-speech engine will not: the
gender and the quality grade behind a machine name such as
`en-us-x-iog-local` on Android or an Apple voice name on iOS.

The labels in the file are English only, so the app never shows them: it
builds every voice name out of its own translations (`voiceLabel` and the
region names in `app_en.arb`) and asks the catalogue only for the gender and
the quality. The labels are kept in the asset because they are what makes an
entry recognisable when the file is read by hand.

Source: [HadrienGardeur/web-speech-recommended-voices](https://github.com/HadrienGardeur/web-speech-recommended-voices),
licensed CC0-1.0 (public domain dedication), reduced to the fields the app
needs by `tool/fetch_voices.py`. That project moved its JSON files to
[Readium Speech](https://github.com/readium/speech) in December 2025 and now
keeps them only in its history; the script reads the last commit that still
has them, because that copy is the CC0 one.

Re-run `python3 tool/fetch_voices.py` from `app/` to pick up new voices, and
commit the result: the app reads the asset, never the network.
