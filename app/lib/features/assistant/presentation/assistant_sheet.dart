import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/router.dart';
import '../../../app/shell_layout.dart';
import '../../../app/theme.dart';
import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/device_position_request.dart';
import '../../map/presentation/map_chrome.dart';
import '../../map/presentation/visible_map_padding.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/domain/avoid_area.dart';
import '../../planner/domain/planner_state.dart';
import '../../planner/domain/route_profile.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/adaptive_docking_sheet.dart';
import '../../shared/presentation/ai_mark.dart';
import '../../shared/presentation/docking_sheet.dart';
import '../../shared/presentation/stat_tile.dart';
import '../../subscription/application/plus_access.dart';
import '../application/assistant_controller.dart';
import '../application/assistant_sheet_memory.dart';
import '../application/route_advice_controller.dart';
import '../data/ai_consent_controller.dart';
import '../domain/ai_consent.dart';
import '../domain/assistant_state.dart';
import '../domain/intent_resolver.dart';
import 'ai_consent_dialog.dart';
import 'assistant_strings.dart';

export '../application/assistant_sheet_memory.dart' show AssistantMode;

/// "A hilly 60 km loop from here past the lake", as a text field; or, with a
/// route on the map, a question about it.
///
/// The AI's card, in the Plan tab's sheet slot in place of the planner's
/// card: it rests as high as the planner's card rests, under the same bar
/// and beside the same rail, turned with the shell sideways, and is pulled up
/// to read a long answer. It is no modal: the map above it is the planner's
/// map as ever, panned, zoomed and tapped as with the planner's card up.
///
/// It goes with [onClose]: swiped away (`null`), or with the intent that was
/// handed over — a [LoopIntent] means a loop search is already running and
/// the planner should show the loop sheet, a [RouteIntent] means the
/// waypoints are on the map. Gone, it keeps what it showed: see
/// [AssistantSheetMemory] and [RouteAdviceController].
class AssistantSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const AssistantSheet({
    required this.onClose,
    super.key,
    this.map,
    this.chromeTop = defaultMapControlsTop,
    this.onExtent,
    this.openFull = false,
  });

  /// The planner's map, used to bias the geocoder towards what is on screen
  /// and to show what an answer about the route points at.
  final MapController? map;

  /// Called once the card is to go, with what it handed over, if anything.
  final ValueChanged<ResolvedIntent?> onClose;

  /// How far the planner's chrome reaches below the safe area, which a
  /// place or a stretch shown on the map keeps clear of.
  final double chromeTop;

  /// Called with the share of the screen's length the card covers, as the
  /// planner's sheet reports its extent, for the tab that comes next.
  final ValueChanged<double>? onExtent;

  /// Whether the card opens all the way rather than at rest: over a
  /// planner's card pulled up past its rest, which would otherwise show
  /// above it.
  final bool openFull;

  @override
  ConsumerState<AssistantSheet> createState() => _AssistantSheetState();
}

/// The key of the assistant sheet's surface, for tests that measure it.
const Key assistantSheetSurfaceKey = ValueKey<String>('assistant-sheet');

/// The key of the paint that draws the AI card's edge, for tests.
const Key assistantSheetEdgeKey = ValueKey<String>('assistant-sheet-edge');

/// The corner radius of the assistant card, the planner card's at rest.
const double _cornerRadius = 28;

class _AssistantSheetState extends ConsumerState<AssistantSheet> {
  final TextEditingController _prompt = TextEditingController();
  final TextEditingController _question = TextEditingController();
  final GlobalKey _sheetKey = GlobalKey();
  final DraggableScrollableController _sheet = DraggableScrollableController();

  /// The content's own controller: a drag on the content scrolls it at
  /// whatever height the sheet has, and only the handle moves the sheet.
  final ScrollController _contentScroll = ScrollController();

  /// The "part of Velorki Plus" row, to bring it into view when it comes.
  final GlobalKey _notEntitledKey = GlobalKey();

  /// The text field with Ask under it, to bring them into view when a chip
  /// fills the field and when the keyboard comes up.
  final GlobalKey _fieldKey = GlobalKey();

  /// The answer (or what the model asked for) and the error under the
  /// field, to scroll to when they arrive.
  final GlobalKey _answerKey = GlobalKey();
  final GlobalKey _problemKey = GlobalKey();

  /// The drag on the handle under way, fed to the sheet's own position so
  /// that the sheet snaps on release as the planner's card does.
  Drag? _drag;

  /// The sheet's stops of the last build, and the list of the one it snaps
  /// to between them, kept while it holds: a new list makes the sheet snap
  /// again.
  SheetStops? _stops;
  List<double> _snapSizes = const [];

  /// Whether the scrollbar shows by itself for a moment: the content has
  /// grown past what the card shows, and the rider should see there is more.
  bool _flashScrollbar = false;
  Timer? _flashTimer;

  /// How far the content could scroll at the last look.
  double _contentExtent = 0;

  /// The room the sheet had at its last build, to keep its height through
  /// the keyboard coming and going.
  double? _room;

  late final AssistantSheetMemory _memory;

  /// Whether the route on the map may be asked about: decided when the
  /// sheet opens, and changed only once the plan has a route or is cleared,
  /// since a fix being applied re-routes the plan and the choice of
  /// modes must not flicker while it does. See [_planChanged].
  late bool _routeAvailable;
  late AssistantMode _mode;

  /// Whether the focus is in the card: only then does it rise over the
  /// keyboard. The planner's search field, above it, opens the keyboard
  /// too, and the card then stays under it as the planner's card does.
  bool _focused = false;

  /// The quarter turns and the stops of the last build: a turn of the phone
  /// keeps the card where the rider left it among the new stops.
  int? _turns;

  /// The screen's length along the card's travel, at the last build.
  double _length = 0;

  @override
  void initState() {
    super.initState();
    _memory = ref.read(assistantSheetMemoryProvider);
    _prompt.text = _memory.prompt.isNotEmpty
        ? _memory.prompt
        : ref.read(assistantControllerProvider).prompt;
    _question.text = _memory.question;
    _routeAvailable = canAskAboutRoute(ref.read(plannerControllerProvider));
    _mode = _routeAvailable
        ? _memory.mode ?? AssistantMode.thisRoute
        : AssistantMode.newRoute;
    _empty = _field.text.trim().isEmpty;
    // The chips under the field follow what is in it.
    _prompt.addListener(_promptChanged);
    _question.addListener(_promptChanged);
    _showField();
  }

  /// At rest under the bar the card shows the head of its content; the
  /// field is what the rider came for, so it is in view from the start and
  /// after a turn of the phone, the head scrolled up as far as that takes.
  void _showField() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _fieldAboveEnd());

  /// What lies over the content's end at the last build: the floating bar
  /// and the safe area upright, nothing over the keyboard.
  double _coveredEnd = 0;

  /// Scrolls the content, if it has to, so that the field and Ask under it
  /// end above what covers the content's end.
  void _fieldAboveEnd() {
    final target = _fieldKey.currentContext?.findRenderObject();
    if (!mounted ||
        target == null ||
        !target.attached ||
        !_contentScroll.hasClients) {
      return;
    }
    final position = _contentScroll.position;
    final end =
        RenderAbstractViewport.of(target).getOffsetToReveal(target, 1).offset +
        _coveredEnd;
    final to = end.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (to > position.pixels + 0.5) position.jumpTo(to);
  }

  bool _empty = true;

  TextEditingController get _field =>
      _mode == AssistantMode.thisRoute ? _question : _prompt;

  void _promptChanged() {
    _memory
      ..prompt = _prompt.text
      ..question = _question.text;
    final empty = _field.text.trim().isEmpty;
    if (empty != _empty) setState(() => _empty = empty);
  }

  void _setMode(AssistantMode mode) {
    if (mode == _mode) return;
    _memory.mode = mode;
    setState(() {
      _mode = mode;
      _empty = _field.text.trim().isEmpty;
    });
  }

  /// Clears the question, the answer and its findings of the mode on
  /// screen; the mode stays, and the loop the assistant made is no longer
  /// news.
  void _startOver() {
    _memory.loop = null;
    if (_mode == AssistantMode.thisRoute) {
      ref.read(routeAdviceControllerProvider.notifier).reset();
      _question.clear();
    } else {
      ref.read(assistantControllerProvider.notifier).reset();
      _prompt.clear();
    }
  }

  /// Appends [wish] to what the rider typed.
  void _add(String wish) {
    final text = _prompt.text.trimRight();
    final sep = text.isEmpty || text.endsWith(',') ? ' ' : ', ';
    _prompt.value = TextEditingValue(
      text: '$text$sep$wish',
      selection: TextSelection.collapsed(offset: '$text$sep$wish'.length),
    );
    setState(() {});
    _revealField();
  }

  /// Puts [text] in the field, as a chip under it does.
  void _fill(TextEditingController field, String text) {
    field.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _revealField();
  }

  /// Scrolls the field back into view after a chip filled it: a chip far
  /// down the list, under an answer, would leave the rider looking at
  /// chips while the question changed out of sight.
  void _revealField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final field = _fieldKey.currentContext;
      if (!mounted || field == null || !field.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          field,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  /// How high the keyboard stood under the card at the last build, while
  /// the focus was in it.
  double _keyboard = 0;

  /// The keyboard is coming up under the card: the field and Ask under it
  /// are kept in view over it, not only the line being typed in.
  void _keepFieldOverKeyboard(double keyboard) {
    final before = _keyboard;
    _keyboard = keyboard;
    if (keyboard <= before) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fieldAboveEnd());
  }

  @override
  void dispose() {
    _prompt
      ..removeListener(_promptChanged)
      ..dispose();
    _question
      ..removeListener(_promptChanged)
      ..dispose();
    _drag?.cancel();
    _flashTimer?.cancel();
    _sheet.dispose();
    _contentScroll.dispose();
    super.dispose();
  }

  /// The wishes the planner acts on that the prompt does not mention yet.
  List<String> _wishes(AppLocalizations l10n) {
    final said = _prompt.text.toLowerCase();
    return <String>[
      l10n.assistantRefineFlat,
      l10n.assistantRefineHilly,
      l10n.assistantRefineGravel,
      l10n.assistantRefineQuiet,
      l10n.assistantRefineLoop,
    ].where((w) => !said.contains(w.toLowerCase())).toList(growable: false);
  }

  /// The questions offered about the route on the map.
  List<String> _routeExamples(AppLocalizations l10n) => <String>[
    l10n.assistantRouteExampleCheck,
    l10n.assistantRouteExampleCoffee,
    l10n.assistantRouteExampleWater,
    l10n.assistantRouteExampleAvoid,
    l10n.assistantRouteExampleRoadBike,
  ];

  /// Makes sure there is a consent, asking for one exactly once.
  ///
  /// Answers `null` when the rider dismissed the dialog or refused, in which
  /// case nothing is sent and nothing is said.
  Future<AiConsent?> _ensureConsent() async {
    final stored = ref.read(aiConsentControllerProvider);
    if (stored != null && stored.allowsRequests) return stored;
    final choice = await showAiConsentDialog(context);
    if (choice == null) return null;
    await ref.read(aiConsentControllerProvider.notifier).set(choice);
    return choice.allowsRequests ? choice : null;
  }

  Future<void> _send() async {
    if (_mode == AssistantMode.thisRoute) return _askAboutRoute();
    final text = _prompt.text.trim();
    if (text.isEmpty) return;
    final consent = await _ensureConsent();
    if (consent == null || !mounted) return;
    // The position is needed locally in any case — "from here" is resolved on
    // the phone — and is only ever *sent* with AiConsent.withLocation.
    final position = await requestDevicePosition(context, ref);
    if (!mounted) return;
    await ref
        .read(assistantControllerProvider.notifier)
        .submit(text, position: position, bias: widget.map?.center);
  }

  /// Asks about the route on the map. No position is asked for: the route
  /// is what the question is about.
  Future<void> _askAboutRoute() async {
    final text = _question.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    final consent = await _ensureConsent();
    if (consent == null || !mounted) return;
    await ref.read(routeAdviceControllerProvider.notifier).ask(text);
  }

  Future<void> _choose(String query, ResolvedPlace place) async {
    final position = await requestDevicePosition(context, ref);
    if (!mounted) return;
    await ref
        .read(assistantControllerProvider.notifier)
        .choose(query, place, position: position, bias: widget.map?.center);
  }

  /// Brings the "part of Velorki Plus" row into view once it appears; the
  /// rider may have scrolled the content since the sheet opened.
  void _revealProblem(bool? before, bool now) {
    if (!now || before == true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _notEntitledKey.currentContext;
      if (!mounted || row == null || !row.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          row,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          duration: const Duration(milliseconds: 200),
        ),
      );
    });
  }

  /// What of the map is neither under this card nor under the planner's
  /// chrome and control column, as padding for the camera: the card rises
  /// from the bottom upright and comes out from a side sideways.
  EdgeInsets _uncovered() {
    final media = MediaQuery.of(context);
    final size = media.size;
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    final sheet = box == null || !box.hasSize
        ? Rect.fromLTWH(0, size.height, size.width, 0)
        : MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          );
    var left = 24.0;
    var right = 24.0 + mapControlsWidth(context);
    var bottom = 24.0;
    final top = media.viewPadding.top + widget.chromeTop + 24;
    // A card that leaves next to nothing still gets a sliver to aim at.
    if (sheet.height >= size.height - 1 && sheet.width < size.width - 1) {
      right = 24;
      final covered = math.min(sheet.width + 24, size.width - 160);
      if (sheet.center.dx < size.width / 2) {
        left = covered;
      } else {
        right = covered;
      }
    } else {
      bottom = math.min(size.height - sheet.top + 24, size.height - top - 120);
    }
    return EdgeInsets.fromLTRB(left, top, right, math.max(bottom, 24));
  }

  /// Moves the map to what finding [finding] is about: its place, which the
  /// map then marks with its name and its kind's icon (see
  /// [RouteAdviceState.shown]), or its stretch of the route on the map.
  ///
  /// Without [mark] the place is only moved to: a stop just added has its
  /// waypoint there.
  void _show(
    RouteFinding finding,
    RouteAdviceState advice, {
    bool mark = true,
  }) {
    final map = widget.map;
    if (map == null) return;
    final place = advice.placeOf(finding.placeId ?? _stopOf(finding));
    final padding = _uncovered();
    if (place != null) {
      if (mark) ref.read(routeAdviceControllerProvider.notifier).show(place);
      unawaited(
        map.moveTo(
          LatLng(place.at.lat, place.at.lon),
          zoom: 15,
          padding: padding,
        ),
      );
      return;
    }
    final route = ref.read(plannerControllerProvider).result ?? advice.route;
    final from = finding.fromKm;
    if (route == null || from == null) return;
    final to = finding.toKm ?? from;
    final piece = AvoidArea.cut(
      route.positions,
      from * 1000,
      math.max(to * 1000, from * 1000 + 1),
    );
    if (piece.isEmpty) return;
    if (to - from < 0.2) {
      unawaited(map.moveTo(piece.first, zoom: 15, padding: padding));
    } else {
      unawaited(map.fitBounds(BoundingBox.fromPoints(piece), padding: padding));
    }
  }

  /// Applies the fix of finding [index] and, when it went in, shows on the
  /// map where it changed the route: a stop next to the line changes the
  /// line by a few metres at most, so the new stop is what there is to see.
  void _apply(int index, RouteAdviceState advice) {
    final finding = advice.advice!.findings[index];
    final applied = ref
        .read(routeAdviceControllerProvider.notifier)
        .apply(index);
    if (applied && finding.fix is! ProfileFix) {
      _show(finding, advice, mark: false);
    }
  }

  /// The handle's drag, fed to the sheet's own scroll position: the sheet
  /// follows it and, let go, snaps to the nearest of its stops, or the next
  /// one the way it was flung, exactly as the planner's card does. Along the
  /// sheet's travel, which sideways is across the screen.
  Map<Type, GestureRecognizerFactory> _handleDrag(ScrollController sheet) =>
      <Type, GestureRecognizerFactory>{
        VerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
              VerticalDragGestureRecognizer.new,
              (recognizer) {
                recognizer
                  ..onStart = (details) {
                    if (!sheet.hasClients) return;
                    _drag?.cancel();
                    _drag = sheet.position.drag(details, () => _drag = null);
                  }
                  ..onUpdate = (details) {
                    _drag?.update(details);
                  }
                  ..onEnd = _release
                  ..onCancel = () {
                    _drag?.cancel();
                    _drag = null;
                  };
              },
            ),
      };

  /// Lets go of the handle. Where the planner's card docks below its
  /// resting height, this one goes: flung away, or let go nearer its lowest
  /// stop than its resting one. Let go lower but not away, it goes back to
  /// rest; anywhere else it snaps as the planner's card does.
  void _release(DragEndDetails details) {
    final drag = _drag;
    _drag = null;
    final stops = _stops;
    if (drag == null) return;
    if (stops == null || !_sheet.isAttached) {
      drag.end(details);
      return;
    }
    final size = _sheet.size;
    // Towards the sheet's end, which closes it.
    final fling = details.primaryVelocity ?? 0;
    final below = size < stops.resting - 0.001;
    if (below &&
        (fling > 700 || size < (stops.collapsed + stops.resting) / 2)) {
      drag.cancel();
      widget.onClose(null);
      return;
    }
    drag.end(
      below && fling > 0
          ? DragEndDetails(primaryVelocity: 0, velocity: Velocity.zero)
          : details,
    );
  }

  /// The one point the sheet snaps to between its lowest and highest stop:
  /// the same list while it holds, see [_snapSizes].
  List<double> _snapSizesFor(double resting) {
    if (_snapSizes.length != 1 || _snapSizes.first != resting) {
      _snapSizes = <double>[resting];
    }
    return _snapSizes;
  }

  /// Shows the scrollbar for a moment when the content grows past what the
  /// card shows: an answer arriving under the fold.
  bool _contentMetrics(ScrollMetricsNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    final extent = metrics.maxScrollExtent;
    final grew = extent > _contentExtent + 1;
    _contentExtent = extent;
    if (grew && extent > 0) {
      _flashTimer?.cancel();
      if (!_flashScrollbar) setState(() => _flashScrollbar = true);
      _flashTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _flashScrollbar = false);
      });
    }
    return false;
  }

  /// Scrolls the content, smoothly, so that what [key] marks starts near
  /// the top of what the card shows: an answer or an error that just came.
  void _reveal(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext?.findRenderObject();
      if (!mounted || target == null || !_contentScroll.hasClients) return;
      final position = _contentScroll.position;
      final offset = RenderAbstractViewport.of(target)
          .getOffsetToReveal(target, 0)
          .offset;
      // A little of what came before stays in view, so it reads as the
      // answer to it.
      final to = (offset - 12).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((to - position.pixels).abs() < 1) return;
      unawaited(
        position.animateTo(
          to,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  /// How tall the rider left the sheet, in dp, once they moved it; `null`
  /// while it rests where it opened.
  double? _heightDp;

  /// Keeps the sheet as many dp tall when its [room] changes, which is the
  /// keyboard coming or going: a share of the room would shrink it to a
  /// sliver over the keyboard. A sheet left where it opened follows its
  /// resting height by itself, which is in dp already.
  void _keepHeight(double room, double max) {
    final before = _room;
    _room = room;
    final height = _heightDp;
    if (before == null || before == room || height == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheet.isAttached || room <= 0) return;
      _sheet.jumpTo((height / room).clamp(0.0, max));
    });
  }

  bool _sheetMoved(DraggableScrollableNotification notification) {
    final room = _room;
    if (room != null) {
      _heightDp = notification.extent * room;
      _reportExtent(notification.extent * room);
    }
    return false;
  }

  /// Tells the planner how much of the screen's length the card covers,
  /// [dp] of it.
  void _reportExtent(double dp) {
    if (_length > 0) widget.onExtent?.call((dp / _length).clamp(0.0, 1.0));
  }

  /// The phone turned since the last build: the card is moved, after this
  /// frame, to the same place among the new stops as it had among the old
  /// ones, as the planner's card is ([AdaptiveDockingSheet]). Its height in
  /// dp means nothing the other way up.
  void _keepPlace(int turns, SheetStops? from, SheetStops to) {
    final before = _turns;
    _turns = turns;
    if (before == null || before == turns || from == null) return;
    _heightDp = null;
    if (!_sheet.isAttached) return;
    final target = mapSheetExtent(_sheet.size, from: from, to: to);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _sheet.isAttached) _sheet.jumpTo(target);
      _showField();
    });
  }

  /// The plan changed under the card: a route that came makes "This route"
  /// a choice, and a plan with no route left takes it away.
  void _planChanged(PlannerState? before, PlannerState now) {
    final can = canAskAboutRoute(now);
    if (can == _routeAvailable) return;
    // Routed again, by a fix or a waypoint the rider moved, or failing to
    // be: the choice stays for as long as there is a plan.
    if (!can && now.hasPoints) return;
    setState(() {
      _routeAvailable = can;
      if (!can) _mode = AssistantMode.newRoute;
      _empty = _field.text.trim().isEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    // The tab's own: its padding counts the bar, or the rail sideways,
    // as the planner's card's does.
    final layout = ShellLayout.of(context);
    final geometry = SheetGeometry.of(context);
    final turns = shellQuarterTurns(layout);
    _length = geometry.length;

    ref.listen(assistantControllerProvider, (previous, next) {
      if (next.phase != AssistantPhase.ready || !mounted) return;
      if (previous?.phase == AssistantPhase.ready) return;
      // Everything that could be done has been done: a loop search is running
      // or the waypoints are on the map. The planner takes it from here.
      widget.onClose(next.intent);
    });
    ref.listen(plannerControllerProvider, _planChanged);
    ref.listen(
      assistantControllerProvider.select((s) => _notEntitled(s.problem)),
      _revealProblem,
    );
    // An answer or an error that came: scrolled to, wherever the rider had
    // scrolled the content. Not having Plus is shown above, see above.
    ref.listen(assistantControllerProvider, (before, now) {
      if (_mode != AssistantMode.newRoute || before?.busy != true) return;
      if (now.busy || now.phase == AssistantPhase.ready) return;
      if (now.problem != null && !_notEntitled(now.problem)) {
        _reveal(_problemKey);
      } else if (now.request != null) {
        _reveal(_answerKey);
      }
    });
    ref.listen(routeAdviceControllerProvider, (before, now) {
      if (_mode != AssistantMode.thisRoute || before?.busy != true) return;
      if (now.busy) return;
      if (now.problem != null && !_notEntitled(now.problem)) {
        _reveal(_problemKey);
      } else if (now.advice != null) {
        _reveal(_answerKey);
      }
    });
    ref.listen(
      routeAdviceControllerProvider.select((s) => _notEntitled(s.problem)),
      _revealProblem,
    );

    // No barrier: outside the card, every touch is the map's, or the
    // planner chrome's over it. The sheet below takes only its own.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused != _focused) setState(() => _focused = focused);
      },
      child: QuarterTurnedFrame(
        quarterTurns: turns,
        child: Builder(
          builder: (context) => _turnedSheet(context, geometry, turns),
        ),
      ),
    );
  }

  /// The sheet in the frame turned with the shell: rising from the frame's
  /// bottom, over the keyboard while the focus is in it, its content turned
  /// back upright.
  Widget _turnedSheet(BuildContext context, SheetGeometry geometry, int turns) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final layout = ShellLayout.of(context);
    final sideways = turns != 0;
    // Sideways the turned sheet's end lies under the rail: the content,
    // upright again, keeps clear of it there, as the planner's does.
    final end = sideways ? geometry.endInset : 0.0;
    return Padding(
      padding: EdgeInsets.only(bottom: _focused ? media.viewInsets.bottom : 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.maxHeight;
          // The phone's own safe area at the far end, turned with the frame.
          final view = View.of(context);
          final far = turnInsets(
            EdgeInsets.fromViewPadding(view.viewPadding, view.devicePixelRatio),
            turns,
          ).top;
          // As far open as the planner's card, and never past the safe
          // area at the far end.
          final safe = room <= 0
              ? 1.0
              : ((room - far - 8) / room).clamp(0.3, 1.0);
          final max = room <= 0
              ? 1.0
              : math.min(geometry.length * sheetMaxExtent / room, safe);
          // At rest as the planner's card rests.
          final rest = room <= 0
              ? 0.5
              : (geometry.restingDp / room).clamp(0.2, max);
          // Where the planner's card docks, this one goes; see [_release].
          final before = _stops;
          _stops = SheetStops(collapsed: rest * 0.5, resting: rest, max: max);
          _keepPlace(turns, before, _stops!);
          _keepHeight(room, max);
          return NotificationListener<DraggableScrollableNotification>(
            onNotification: _sheetMoved,
            child: DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: widget.openFull ? max : rest,
              minChildSize: rest * 0.5,
              maxChildSize: max,
              snap: true,
              snapSizes: _snapSizesFor(rest),
              builder: (context, scrollController) => Material(
                key: _sheetKey,
                color: theme.colorScheme.surface,
                elevation: 3,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(_cornerRadius),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomPaint(
                  key: assistantSheetEdgeKey,
                  // The AI's card: its top edge in the AI's colours, along
                  // the turned edge sideways.
                  foregroundPainter: AiEdgePainter(
                    gradient: theme.velorki.aiGradient,
                    radius: _cornerRadius,
                  ),
                  child: KeyedSubtree(
                    key: assistantSheetSurfaceKey,
                    child: Column(
                      children: [
                        // The handle alone moves the sheet, either way
                        // up: the content scrolls by itself at any height.
                        RawGestureDetector(
                          behavior: HitTestBehavior.opaque,
                          gestures: _handleDrag(scrollController),
                          // The sheet's own controller has to sit on a
                          // scrollable for the sheet to be moved; the drags
                          // come from the detector around it.
                          child: SingleChildScrollView(
                            controller: scrollController,
                            physics: const NeverScrollableScrollPhysics(),
                            child: const SizedBox(
                              height: sheetHandleDp,
                              width: double.infinity,
                              child: SheetHandle(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: QuarterTurnedFrame(
                            quarterTurns: 4 - turns,
                            // A drag on the content scrolls it, whatever the
                            // sheet's height: the handle moves the sheet.
                            child: !sideways
                                ? _content(context, sideways: false)
                                : Padding(
                                    padding: layout.side == RailSide.left
                                        ? EdgeInsets.only(left: end)
                                        : EdgeInsets.only(right: end),
                                    child: MediaQuery.removePadding(
                                      context: context,
                                      removeLeft: true,
                                      removeRight: true,
                                      child: _keptWide(
                                        _content(context, sideways: true),
                                        railOnLeft: turns == 1,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// [content] kept as wide as a sideways sheet's content at rest while
  /// the sheet is pushed away towards the rail, going under the screen's
  /// edge there as the tabs' sheets do: narrowing it would break its rows.
  Widget _keptWide(Widget content, {required bool railOnLeft}) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= sidewaysSheetContentWidth) {
        return content;
      }
      return ClipRect(
        child: OverflowBox(
          minWidth: sidewaysSheetContentWidth,
          maxWidth: sidewaysSheetContentWidth,
          alignment: railOnLeft ? Alignment.centerRight : Alignment.centerLeft,
          child: content,
        ),
      );
    },
  );

  /// What the sheet holds, upright: one list, Ask in it under the field.
  Widget _content(BuildContext context, {required bool sideways}) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(assistantControllerProvider);
    final advice = ref.watch(routeAdviceControllerProvider);
    final aboutRoute = _mode == AssistantMode.thisRoute;
    final busy = aboutRoute ? advice.busy : state.busy;
    // A fix being routed counts too: the next question is about the route
    // it makes.
    final routing =
        aboutRoute &&
        ref.watch(plannerControllerProvider.select((s) => s.isRouting));
    // While anything runs, nothing in the sheet takes input; the text stays
    // readable. Show on the map stays, it changes nothing.
    final locked = busy || routing;
    final problem = aboutRoute ? advice.problem : state.problem;
    final notEntitled = _notEntitled(problem) ? problem : null;
    final canStartOver = aboutRoute
        ? !advice.isEmpty || _question.text.isNotEmpty
        : state != const AssistantState() || _prompt.text.isNotEmpty;
    final media = MediaQuery.of(context);
    // Over the keyboard, nothing of the bar or the safe area is in the way;
    // under the keyboard (the planner's search has it) nothing shows anyway.
    final keyboard = media.viewInsets.bottom > 0;
    _keepFieldOverKeyboard(_focused ? media.viewInsets.bottom : 0);
    // Upright the bar floats over the card's end, as over the planner's
    // card; sideways the rail is beside the content, and the home
    // indicator under it.
    final bottomSafe = keyboard ? 0.0 : media.padding.bottom;
    _coveredEnd = bottomSafe;
    // Sideways the keyboard comes up across the card, not under it: the
    // content keeps above it.
    final lift = sideways && _focused ? media.viewInsets.bottom : 0.0;
    final plusMissing =
        ref.watch(plusAccessProvider(PlusFeature.aiAssistant)) ==
        PlusAccess.missing;
    // The loop the assistant asked the loop search for, now on the map: what
    // was asked for stays in view above the question about it, for as long
    // as the plan is that loop.
    final handover = _memory.loop;
    final ends = ref.watch(plannerControllerProvider.select(planEnds));
    final loopMade =
        aboutRoute &&
        handover != null &&
        handover.found &&
        identical(state.intent, handover.intent) &&
        state.request != null &&
        ends == handover.ends;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Only with a route to ask about is there a choice.
          if (_routeAvailable) ...[
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<AssistantMode>(
                segments: [
                  ButtonSegment(
                    value: AssistantMode.thisRoute,
                    label: Text(l10n.assistantModeRoute),
                    icon: const Icon(Icons.route_rounded),
                  ),
                  ButtonSegment(
                    value: AssistantMode.newRoute,
                    label: Text(l10n.assistantModeNew),
                    icon: const Icon(Icons.add_road_rounded),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: locked
                    ? null
                    : (selected) => _setMode(selected.single),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            aboutRoute ? l10n.assistantRouteTitle : l10n.assistantTitle,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          // What leaves the phone and what does not: said in the
          // reading size, not in fine print.
          Text(
            aboutRoute ? l10n.assistantRouteIntro : l10n.assistantIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    // Known to be without Plus, the sheet is there to look around in,
    // and where Ask would be it says what Ask needs. While the store
    // has not answered, Ask is offered and the relay decides.
    final actions = plusMissing
        ? const PlusRequiredBanner()
        : Row(
            children: [
              if (canStartOver) ...[
                TextButton.icon(
                  onPressed: locked ? null : _startOver,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(l10n.assistantStartOver),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                // The button is locked while it works, so it says what is
                // going on: a line above it would be under the keyboard.
                child: FilledButton.icon(
                  onPressed: locked ? null : () => unawaited(_send()),
                  icon: locked
                      ? const ButtonProgress()
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(
                    !locked
                        ? l10n.assistantSend
                        : !busy
                        ? l10n.plannerRouting
                        : aboutRoute
                        ? (advice.phase == RouteAdvicePhase.reading
                              ? l10n.assistantRouteReading
                              : l10n.assistantThinking)
                        : state.phase == AssistantPhase.asking
                        ? l10n.assistantThinking
                        : l10n.assistantResolving,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          // The platform's scrollbar, while the content scrolls and for a
          // moment when it grows past what the card shows, so an answer
          // under the fold is seen to be there.
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _contentMetrics,
            child: Scrollbar(
              controller: _contentScroll,
              thumbVisibility: _flashScrollbar ? true : null,
              // Not a lazy list: a few rows, and an answer scrolled out of
              // view must still be there to scroll back to.
              child: SingleChildScrollView(
                controller: _contentScroll,
                // Its end clear of the floating bar upright, as the
                // planner's card's list is.
                padding: EdgeInsets.fromLTRB(20, 0, 20, bottomSafe + 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    if (loopMade) ...[
                      AiAnswer(
                        child: _RequestSummary(
                          state: state,
                          note: l10n.assistantLoopOnMap,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Not having Plus is said first, where it is seen, rather
                    // than under the answer it stands in for.
                    if (notEntitled != null) ...[
                      KeyedSubtree(
                        key: _notEntitledKey,
                        child: _ProblemRow(problem: notEntitled),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // The field and Ask right under it, scrolling with the
                    // rest as the planner's card's buttons do.
                    KeyedSubtree(
                      key: _fieldKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            // Keyed by mode, so each keeps its own text and undo.
                            key: ValueKey(_mode),
                            controller: _field,
                            readOnly: locked,
                            // Full width, two lines at least and up to four.
                            minLines: 2,
                            maxLines: 4,
                            maxLength: 1000,
                            // The count only once it matters: it took a line of
                            // its own.
                            buildCounter:
                                (
                                  context, {
                                  required currentLength,
                                  required isFocused,
                                  required maxLength,
                                }) => currentLength > 900
                                ? Text('$currentLength/$maxLength')
                                : null,
                            textInputAction: TextInputAction.send,
                            style: theme.textTheme.bodyLarge,
                            decoration: InputDecoration(
                              hintText: aboutRoute
                                  ? l10n.assistantRouteHint
                                  : l10n.assistantHint,
                            ),
                            onSubmitted: locked
                                ? null
                                : (_) => unawaited(_send()),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: actions,
                          ),
                        ],
                      ),
                    ),
                    if (aboutRoute)
                      ..._routeChildren(l10n, theme, advice, locked: locked)
                    else
                      ..._newRouteChildren(l10n, state, locked: locked),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    final body = lift > 0
        ? Padding(
            padding: EdgeInsets.only(bottom: lift),
            child: column,
          )
        : column;
    // Pulled down on its way out, the card's end goes under the bar and the
    // screen's edge, as the planner's card's does, rather than squeezing the
    // content.
    final least = 140 + bottomSafe + lift;
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxHeight >= least
          ? body
          : ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: least,
                maxHeight: least,
                child: body,
              ),
            ),
    );
  }

  /// Whether [state] is the request the assistant handed to the loop
  /// search, which found no loop for it.
  bool _loopMissed(AssistantState state) {
    final handover = _memory.loop;
    return handover != null &&
        !handover.found &&
        identical(state.intent, handover.intent);
  }

  /// Under the field, asking for a new route: examples or wishes, then what
  /// the model understood, the choices to make and the error.
  List<Widget> _newRouteChildren(
    AppLocalizations l10n,
    AssistantState state, {
    required bool locked,
  }) {
    final wishes = _wishes(l10n);
    return [
      // An empty field gets whole examples; a typed one the wishes the
      // planner acts on, minus those already said.
      if (_empty)
        SectionCaption(l10n.assistantExamples)
      else if (wishes.isNotEmpty)
        SectionCaption(l10n.assistantRefinements),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (_empty)
            for (final example in <String>[
              l10n.assistantExampleFlatLoop,
              l10n.assistantExampleQuietRide,
              l10n.assistantExampleGravel,
            ])
              ActionChip(
                label: Text(example),
                onPressed: locked ? null : () => _fill(_prompt, example),
              )
          else
            for (final wish in wishes)
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: Text(wish),
                onPressed: locked ? null : () => _add(wish),
              ),
        ],
      ),
      if (state.request != null && !state.busy) ...[
        const SizedBox(height: 16),
        AiAnswer(
          key: _answerKey,
          child: _RequestSummary(
            state: state,
            // The loop search it was handed to came back with nothing.
            note: _loopMissed(state) ? l10n.assistantLoopNotFound : null,
            noteIsProblem: true,
          ),
        ),
      ],
      if (state.phase == AssistantPhase.needsChoice)
        for (final choice in state.choices)
          _ChoiceRow(
            choice: choice,
            onSelected: locked
                ? null
                : (place) => unawaited(_choose(choice.query, place)),
          ),
      if (state.problem != null && !_notEntitled(state.problem)) ...[
        const SizedBox(height: 16),
        _ProblemRow(
          key: _problemKey,
          problem: state.problem!,
          onRetry: ref.read(assistantControllerProvider.notifier).clearProblem,
        ),
      ],
    ];
  }

  /// Under the field, asking about the route on the map: example questions,
  /// or once there is an answer the others to ask next, then the answer,
  /// its findings and the error.
  List<Widget> _routeChildren(
    AppLocalizations l10n,
    ThemeData theme,
    RouteAdviceState advice, {
    required bool locked,
  }) {
    final answer = advice.advice;
    final asked = advice.question.toLowerCase();
    final next = _routeExamples(l10n)
        .where((q) => q.toLowerCase() != asked)
        .toList(growable: false);
    final offered = answer != null
        ? next
        : (_empty ? _routeExamples(l10n) : null);
    return [
      // The answer first, right under the question, where the eye is.
      if (answer != null && !advice.busy) ...[
        const SizedBox(height: 8),
        // What the model wrote is the content here, so it is set in the
        // reading size rather than as a caption.
        // Marked as the AI's.
        AiAnswer(
          key: _answerKey,
          child: Text(answer.answer, style: theme.textTheme.bodyLarge),
        ),
        if (answer.findings.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionCaption(l10n.assistantRouteFindings),
          for (var i = 0; i < answer.findings.length; i++)
            _FindingRow(
              finding: answer.findings[i],
              place: advice.placeOf(
                answer.findings[i].placeId ?? _stopOf(answer.findings[i]),
              ),
              applied: advice.applied.contains(i),
              failure: advice.failures[i],
              // A fix applied meanwhile is still being routed; the next
              // one waits for the route it applies to.
              canApply: !locked,
              onShow: widget.map == null
                  ? null
                  : () => _show(answer.findings[i], advice),
              onApply: () => _apply(i, advice),
            ),
        ],
      ],
      if (offered != null) ...[
        if (answer != null) const SizedBox(height: 20),
        SectionCaption(
          answer != null
              ? l10n.assistantRouteFollowUps
              : l10n.assistantExamples,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final question in offered)
              ActionChip(
                label: Text(question),
                onPressed: locked ? null : () => _fill(_question, question),
              ),
          ],
        ),
      ],
      if (advice.problem != null && !_notEntitled(advice.problem)) ...[
        const SizedBox(height: 16),
        _ProblemRow(
          key: _problemKey,
          problem: advice.problem!,
          onRetry: ref
              .read(routeAdviceControllerProvider.notifier)
              .clearProblem,
        ),
      ],
    ];
  }
}

/// Whether [problem] is the rider not having Velorki Plus.
bool _notEntitled(AssistantProblem? problem) =>
    problem?.failure == AssistantFailure.notEntitled;

/// The place an add-stop fix of [finding] names, if it has one.
String? _stopOf(RouteFinding finding) => switch (finding.fix) {
  AddStopFix(:final placeId) => placeId,
  _ => null,
};

/// The icon of a finding of [kind].
IconData _findingIcon(FindingKind kind) => switch (kind) {
  FindingKind.traffic => Icons.directions_car_outlined,
  FindingKind.steep => Icons.trending_up_rounded,
  FindingKind.surface => Icons.texture_rounded,
  FindingKind.water => Icons.water_drop_outlined,
  FindingKind.food => Icons.local_cafe_outlined,
  FindingKind.detour => Icons.alt_route_rounded,
  FindingKind.profile => Icons.directions_bike_rounded,
  FindingKind.other => Icons.info_outline_rounded,
};

/// One finding: what it says, where it is, and what can be done about it.
class _FindingRow extends ConsumerWidget {
  const _FindingRow({
    required this.finding,
    required this.place,
    required this.applied,
    required this.failure,
    required this.canApply,
    required this.onShow,
    required this.onApply,
  });

  final RouteFinding finding;

  /// The digest place it is about, when it names one.
  final DigestPlace? place;
  final bool applied;

  /// Why its fix could not be applied, when it could not.
  final FixFailure? failure;
  final bool canApply;
  final VoidCallback? onShow;
  final VoidCallback onApply;

  /// Where along the route it is, in the rider's units.
  String? _where(AppLocalizations l10n, UnitSystem units) {
    String at(double km) => formatDistance(l10n, units, km * 1000);
    final from = finding.fromKm ?? place?.km;
    if (from == null) return null;
    final to = finding.toKm;
    if (to == null || (to - from).abs() < 0.05) {
      return l10n.assistantFindingAt(at(from));
    }
    return l10n.assistantFindingBetween(at(from), at(to));
  }

  String _fixLabel(AppLocalizations l10n, RouteFix fix) => switch (fix) {
    AddStopFix() => l10n.assistantFixAddStop,
    AvoidFix() => l10n.assistantFixAvoid,
    ProfileFix(:final profile) => l10n.assistantFixProfile(
      profileLabel(l10n, RouteProfile.fromName(profile.json)),
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final where = _where(l10n, ref.watch(unitSystemProvider));
    final fix = finding.fix;
    final located =
        place != null || finding.fromKm != null || finding.toKm != null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              _findingIcon(finding.kind),
              size: 22,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(finding.text, style: theme.textTheme.bodyMedium),
                if (where != null)
                  Text(
                    where,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if ((located && onShow != null) || fix != null)
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (located && onShow != null)
                        TextButton.icon(
                          onPressed: onShow,
                          icon: const Icon(Icons.visibility_outlined),
                          label: Text(l10n.assistantFindingShow),
                        ),
                      if (fix != null && applied)
                        Chip(
                          avatar: Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          label: Text(l10n.assistantFixApplied),
                        )
                      else if (fix != null)
                        FilledButton.tonal(
                          onPressed: canApply ? onApply : null,
                          child: Text(_fixLabel(l10n, fix)),
                        ),
                    ],
                  ),
                if (failure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      switch (failure!) {
                        FixFailure.noRoute => l10n.assistantFixNoRoute,
                        FixFailure.notApplicable =>
                          l10n.assistantFixNotApplicable,
                        FixFailure.routingFailed =>
                          l10n.assistantFixRoutingFailed,
                      },
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a Plus feature's button would be, for a rider known to be without
/// Velorki Plus: what the feature needs, and Subscribe, which opens the
/// paywall over the sheet. Back subscribed, the button is there again and
/// whatever was typed with it.
class PlusRequiredBanner extends StatelessWidget {
  /// Creates the banner.
  const PlusRequiredBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.workspace_premium_outlined,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l10n.assistantPlusRequired,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: () => unawaited(context.push<void>(paywallRoute)),
          child: Text(l10n.plusSubscribe),
        ),
      ],
    );
  }
}

/// A spinner the size of a button's icon, for a button that is working.
class ButtonProgress extends StatelessWidget {
  /// Creates the spinner.
  const ButtonProgress({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// What the model asked for, once it is resolved enough to show.
class _RequestSummary extends ConsumerWidget {
  const _RequestSummary({
    required this.state,
    this.note,
    this.noteIsProblem = false,
  });

  final AssistantState state;

  /// A line under it: what became of it.
  final String? note;

  /// Whether [note] says that something did not work.
  final bool noteIsProblem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final request = state.request!;
    final distance = formatDistance(
      l10n,
      ref.watch(unitSystemProvider),
      request.distanceKm * 1000,
    );
    final places = switch (state.intent) {
      LoopIntent(:final via) => via,
      RouteIntent(:final places) => places,
      _ => const <ResolvedPlace>[],
    };
    final startLabel = switch (state.intent) {
      LoopIntent(:final start) => start?.label,
      RouteIntent(:final waypoints) => waypoints.first.name,
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          request.loop
              ? l10n.assistantSummaryLoop(distance)
              : l10n.assistantSummaryRoute(distance),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(
          startLabel == null
              ? l10n.assistantStartHere
              : l10n.assistantStartAt(startLabel),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (places.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final place in places)
                Chip(
                  avatar: const Icon(Icons.place_outlined, size: 18),
                  label: Text(place.label),
                ),
            ],
          ),
        ],
        if (note != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                noteIsProblem ? Icons.error_outline : Icons.loop_rounded,
                size: 20,
                color: noteIsProblem
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(note!, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ],
      ],
    );
  }
}

/// The chooser chips for one ambiguous name.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.choice, required this.onSelected});

  final PlaceChoice choice;

  /// `null` while the sheet is busy.
  final ValueChanged<ResolvedPlace>? onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.assistantChoose(choice.query),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in choice.options)
                ActionChip(
                  label: Text(option.label),
                  onPressed: onSelected == null
                      ? null
                      : () => onSelected!(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The error, with the one action that can help.
class _ProblemRow extends StatelessWidget {
  const _ProblemRow({required this.problem, this.onRetry, super.key});

  final AssistantProblem problem;

  /// Clears the error, keeping what was typed; not offered without Plus,
  /// where the paywall is the one thing that helps.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, color: theme.colorScheme.error),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assistantProblemText(l10n, problem),
                style: theme.textTheme.bodyMedium,
              ),
              if (problem.failure == AssistantFailure.notEntitled)
                // Over the sheet: the rider comes back to what they typed,
                // and the error goes by itself once Plus is active.
                TextButton(
                  onPressed: () => unawaited(context.push<void>(paywallRoute)),
                  child: Text(l10n.plusSeeDetails),
                )
              else if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: Text(l10n.assistantRetry),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
