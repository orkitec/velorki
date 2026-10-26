import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';

part 'web_storage_notice.g.dart';

const String _prefsSeen = 'web.storage_notice_seen';

/// Whether the web planner's note on what it keeps in the browser is in
/// view: on a first visit until the reader closes it, remembered across
/// visits, and again whenever they ask for it from the legal chip. The
/// website's own short notice works the same way, and like it this asks
/// nothing: what the planner stores is what it needs to work.
@Riverpod(keepAlive: true)
class WebStorageNotice extends _$WebStorageNotice {
  @override
  bool build() =>
      !(ref.read(sharedPreferencesProvider).getBool(_prefsSeen) ?? false);

  /// Closed by the reader, and not shown again on its own.
  Future<void> dismiss() async {
    state = false;
    await ref.read(sharedPreferencesProvider).setBool(_prefsSeen, true);
  }

  /// Brought back by the reader.
  void show() => state = true;
}
