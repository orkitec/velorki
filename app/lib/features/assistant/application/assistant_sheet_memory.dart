import 'package:riverpod_annotation/riverpod_annotation.dart';

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
}

/// The one [AssistantSheetMemory] of the app.
@Riverpod(keepAlive: true)
AssistantSheetMemory assistantSheetMemory(Ref ref) => AssistantSheetMemory();
