import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../domain/intent_resolver.dart';

part 'assistant_sheet_memory.g.dart';

/// What the assistant sheet is asked about.
enum AssistantMode {
  /// A new route, from a sentence: what the sheet always did.
  newRoute,

  /// The route on the planner's map.
  thisRoute,
}

/// What the assistant sheet was showing when it was swiped away, so it
/// opens again where the rider left it: the mode and what was typed in
/// either field. The answers themselves live in their controllers.
class AssistantSheetMemory {
  /// The mode the sheet was in, or `null` before it was ever opened.
  AssistantMode? mode;

  /// What was typed asking for a new route.
  String prompt = '';

  /// What was typed asking about the route on the map.
  String question = '';

  /// The loop the assistant last handed to the loop search, once the search
  /// is done; `null` when there is none or it is old news.
  LoopHandover? loop;
}

/// What became of a loop the assistant handed to the loop search: the card
/// comes back with it, asking about the loop if one was found and saying
/// so if none was.
class LoopHandover {
  /// Creates the record.
  const LoopHandover({required this.intent, required this.found, this.ends});

  /// The intent that was handed over, the assistant's own.
  final ResolvedIntent intent;

  /// Whether the search put a loop on the map.
  final bool found;

  /// Where the plan with that loop starts and ends: while it still does,
  /// the plan is that loop.
  final (LatLng, LatLng)? ends;
}

/// The one [AssistantSheetMemory] of the app.
@Riverpod(keepAlive: true)
AssistantSheetMemory assistantSheetMemory(Ref ref) => AssistantSheetMemory();
