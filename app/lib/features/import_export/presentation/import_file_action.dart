import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/router.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/track_decoder.dart';

part 'import_file_action.g.dart';

/// One picked file: what the picker called it and what was in it.
class PickedFile {
  /// Creates a picked file.
  const PickedFile({required this.name, required this.bytes});

  /// The file's name including its extension.
  final String name;

  /// Its contents.
  final Uint8List bytes;
}

/// Opens the system file picker and returns the chosen file, or `null` when
/// the user cancelled.
typedef FilePickerCallback = Future<PickedFile?> Function();

/// The file picker the library's import action uses.
///
/// Overridden in widget tests so no platform channel is involved; `null` from
/// the real one means the user backed out.
@Riverpod(keepAlive: true)
FilePickerCallback trackFilePicker(Ref ref) => pickTrackFile;

/// Asks the platform for a `.gpx` or `.fit` file and reads it.
///
/// The extension filter is a convenience only: Android content providers hand
/// out files with all sorts of names and types, so what actually decides the
/// format is [decodeTrack] sniffing the bytes.
Future<PickedFile?> pickTrackFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['gpx', 'fit'],
  );
  if (file == null) return null;
  return PickedFile(name: file.name, bytes: await file.readAsBytes());
}

/// The library's "Import file" app bar action.
///
/// Picks a file, decodes it and pushes the import preview. A file that is
/// neither GPX nor FIT is reported in a snack bar and nothing else happens.
class ImportFileButton extends ConsumerWidget {
  /// Creates the action.
  const ImportFileButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      icon: const Icon(Icons.file_open_outlined),
      tooltip: l10n.libraryImportFile,
      onPressed: () => _pick(context, ref),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final picker = ref.read(trackFilePickerProvider);

    final PickedFile? picked;
    try {
      picked = await picker();
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.importFailedUnreadable)),
      );
      return;
    }
    if (picked == null) return;

    try {
      final candidate = decodeCandidate(
        picked.bytes,
        fileName: picked.name,
        sourceHint: 'picker',
      );
      router.go(importRoute, extra: candidate);
    } on ImportException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(importFailureMessage(l10n, e.failure))),
      );
    }
  }
}

/// The message shown for an [ImportFailure].
String importFailureMessage(AppLocalizations l10n, ImportFailure failure) =>
    switch (failure) {
      ImportFailure.unknownFormat => l10n.importFailedUnknown,
      ImportFailure.malformed => l10n.importFailedMalformed,
      ImportFailure.empty => l10n.importFailedEmpty,
      ImportFailure.unreadable => l10n.importFailedUnreadable,
      ImportFailure.linkUnreachable => l10n.importFailedLink,
      ImportFailure.accountNeeded => l10n.importFailedRwgpsPrivate,
    };
