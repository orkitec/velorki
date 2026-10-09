#!/usr/bin/env python3
"""Every label tool/screenshots.sh waits for or taps, in one language.

    labels.py <lang> <flutter-root>   prints "name<TAB>regex" lines

The labels are read from the app's own `lib/l10n/app_<lang>.arb` and, for the
tooltips Flutter translates itself (Back, Dismiss, Show menu, the tab bar's
"Tab 1 of 4"), from the SDK's `material_<lang>.arb`, so a new language needs
no entry here. A key missing in the language falls back to English, as the app
does. Upper-case names are the captions `StatTile`, `SectionCaption` and the
recording pill render with `toUpperCase()`.
"""
import json
import os
import re
import sys

lang, flutter_root = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
l10n = os.path.join(here, "..", "..", "lib", "l10n")
material_dir = os.path.join(
    flutter_root, "packages", "flutter_localizations", "lib", "src", "l10n")


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


app_en = load(os.path.join(l10n, "app_en.arb"))
app_path = os.path.join(l10n, f"app_{lang}.arb")
app = load(app_path) if os.path.exists(app_path) else {}
material_en = load(os.path.join(material_dir, "material_en.arb"))
material_path = os.path.join(material_dir, f"material_{lang}.arb")
material = load(material_path) if os.path.exists(material_path) else {}


def s(key):
    """The app string, its placeholders left in."""
    value = app.get(key) or app_en.get(key)
    if not isinstance(value, str):
        sys.exit(f"labels.py: no string {key} in app_en.arb")
    return value


def m(key):
    return material.get(key) or material_en[key]


def esc(text):
    return re.escape(text)


def literal(template):
    """The longest run of plain text in a template with {placeholders}."""
    parts = [p.strip() for p in re.split(r"\{[^}]*\}", template)]
    return max(parts, key=len)


def pattern(template, placeholder=".*"):
    """A template as a regex, every {placeholder} matching anything."""
    pieces = re.split(r"(\{[^}]*\})", template)
    return "".join(placeholder if p.startswith("{") else esc(p) for p in pieces)


def exact(text):
    return f"^{esc(text)}$"



turns = [s(k) for k in (
    "navTurnLeft", "navTurnRight", "navTurnSlightLeft", "navTurnSlightRight",
    "navTurnSharpLeft", "navTurnSharpRight", "navKeepLeft", "navKeepRight",
    "navUTurn", "navExitLeft", "navExitRight")]
turns.append(re.split(r"\{", s("navRoundaboutExit"))[0].strip())

labels = {
    "tabbar": esc(m("tabLabel").replace("$tabIndex", "1").replace("$tabCount", "4")),
    "tab_plan": esc(s("tabPlan")),
    "tab_record": esc(s("tabRecord")),
    "tab_library": esc(s("tabLibrary")),
    "tab_settings": esc(s("tabSettings")),
    "back": exact(m("backButtonTooltip")),
    "dismiss": exact(m("modalBarrierDismissLabel")),
    "menu": exact(m("showMenuTooltip")),
    "delete": exact(s("commonDelete")),
    "save": exact(s("commonSave")),
    "import": exact(s("importTitle")),
    "kind_Route": exact(s("importKindRoute")),
    "kind_Ride": exact(s("importKindRide")),
    # A snackbar: Undo on its action, or the end of a "… deleted" / "… added"
    # message.
    "snack": "|".join([
        esc(s("commonUndo")) + "$",
        esc(literal(s("libraryRouteDeleted"))) + "$",
        esc(literal(s("rideDeleted"))) + "$",
        esc(literal(s("importSavedRoute"))),
        esc(literal(s("importSavedRide"))),
    ]),
    "undo": esc(s("commonUndo")),
    "empty_plan": esc(s("plannerEmptyState").rstrip(".")),
    "DISTANCE": esc(s("statDistance").upper()),
    "locate": exact(s("mapLocateMe")),
    "zoom_out": exact(s("mapZoomOut")),
    "offline_entry": exact(s("offlineEntryTitle")),
    "rationale_allow": exact(s("mapLocationRationaleAllow")),
    "download_visible": exact(s("offlineDownloadVisible")),
    "download": exact(s("offlineDialogDownload")),
    "routing_data": esc(s("offlineRoutingTitle")),
    "manage": exact(s("offlineManage")),
    "tile_update": exact(s("routingTilesUpdate")),
    # The dialog's button for one tile: the `=1{…}` case of its plural,
    # up to the size.
    "tile_download": "^" + esc(
        re.search(r"=1\{([^{}]*)", s("routingTilesDownloadCount")).group(1).rstrip(" (")),
    "search_hint": exact(s("searchHint")),
    "search_clear": "^" + esc(s("searchClear")),
    "hit_monte": esc(f"{s('searchKindSuburb')} · Funchal"),
    "hit_funchal": f"{esc(s('searchKindCity'))}$|{esc(s('searchKindLocality'))} · Funchal",
    "route_here": exact(s("placeCardRouteHere")),
    "place_close": exact(s("placeCardClose")),
    "remove_point": exact(s("plannerRemovePoint")),
    "save_route": exact(s("plannerSaveDialogTitle")),
    "default_route_name": "^" + pattern(s("plannerDefaultRouteName")),
    "loop_make": exact(s("loopMake")),
    "loop_result": "|".join([
        pattern(s("loopResult")),
        esc(s("loopNoneFound").split(",")[0].split(";")[0]),
        esc(re.sub(r"[\s:]+$", "", literal(s("loopFailed")))),
    ]),
    "loop_done": exact(s("loopDone")),
    "loop_stop": exact(s("loopStop")),
    "follow_route": "^" + esc(s("recordingFollowRoute")),
    "no_route": s("recordingFollowNone"),
    "start_ride": exact(s("recordingStart")),
    # Two dialogs say it: the battery one and the location rationale.
    "not_now": exact(s("recordingBatteryLater")),
    "RECORDING": esc(s("recordingStatusRecording").upper()),
    "finish": exact(s("recordingFinish")),
    "ride_save": exact(s("rideSaveTitle")),
    "discard": exact(s("rideSaveDiscard")),
    "recovery_title": exact(s("recordingRecoveryTitle")),
    "recovery_discard": exact(s("recordingRecoveryDiscard")),
    "lib_routes": exact(s("libraryRoutes")),
    "lib_rides": exact(s("libraryRides")),
    "open_in_planner": "^" + esc(s("routeDetailOpenInPlanner")),
    "SLOW": esc(s("rideSpeedSlow").upper()),
    "turn": "^(" + "|".join(esc(t) for t in turns) + ")",
    "metres": "^" + pattern(s("navDistanceMetres"), "[0-9]+") + "$",
    "settings_plus": exact(s("plusTitle")),
    # Labels as they stand in the planner's merged row of actions, for
    # `ui.py slot`: plain text, not patterns.
    "row_clear": s("plannerClear"),
    "row_loop": s("loopAction"),
}

for name, regex in labels.items():
    print(f"{name}\t{regex}")
