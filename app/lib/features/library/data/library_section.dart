import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';

const String _prefsSection = 'library.section';

/// Which half of the Library tab is showing.
enum LibrarySection {
  /// The saved routes.
  routes,

  /// The recorded rides.
  rides;

  /// The section named [name], or [routes] when the name is unknown.
  static LibrarySection fromName(String? name) => LibrarySection.values
      .firstWhere((section) => section.name == name, orElse: () => routes);
}

/// The Library's section switch, kept in shared_preferences so the tab comes
/// back on the half the rider left it on.
class LibrarySectionSetting extends Notifier<LibrarySection> {
  @override
  LibrarySection build() => LibrarySection.fromName(
    ref.watch(sharedPreferencesProvider).getString(_prefsSection),
  );

  /// Shows [section] and remembers the choice.
  Future<void> select(LibrarySection section) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (section == LibrarySection.routes) {
      await prefs.remove(_prefsSection);
    } else {
      await prefs.setString(_prefsSection, section.name);
    }
    state = section;
  }
}

/// The section the Library shows.
final librarySectionProvider =
    NotifierProvider<LibrarySectionSetting, LibrarySection>(
      LibrarySectionSetting.new,
    );
