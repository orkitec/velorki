import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../domain/recording_state.dart';

/// Name of the file that says whether a recording is under way.
const String recordingStateFileName = 'recording_state.json';

/// Extension of a journal file: "velorki track journal".
const String recordingJournalExtension = '.vtj';

/// Appends fixes to `<appSupport>/recording/<rideId>.vtj`.
///
/// Every fix is written through to the file as a 36-byte
/// `PackedTrack.encodePoint` record, so killing the app loses nothing; the
/// expensive `fsync` only happens every [flushEveryPoints] fixes or
/// [flushInterval], which is what a power cut may cost.
///
/// All writes go through one future chain, so appends, flushes and the close
/// at the end of a ride can never interleave.
class RecordingJournal {
  /// Creates a journal over [file].
  RecordingJournal({
    required this.file,
    DateTime Function()? clock,
    this.flushEveryPoints = 5,
    this.flushInterval = const Duration(seconds: 10),
  }) : _clock = clock ?? DateTime.now;

  /// The journal file.
  final File file;

  /// Fixes between two flushes to disk.
  final int flushEveryPoints;

  /// Time between two flushes to disk.
  final Duration flushInterval;

  final DateTime Function() _clock;

  RandomAccessFile? _handle;
  Future<void> _queue = Future<void>.value();
  int _pointCount = 0;
  int _sinceFlush = 0;
  DateTime? _lastFlush;

  /// How many whole records the file holds.
  int get pointCount => _pointCount;

  /// Whether the journal is open for writing.
  bool get isOpen => _handle != null;

  /// Opens the file for appending, writing the header when it is new.
  ///
  /// A trailing partial record — what a crash mid-write leaves behind — is
  /// truncated away first, so the records stay aligned.
  Future<void> open() async {
    if (_handle != null) return;
    await file.parent.create(recursive: true);
    final length = await file.exists() ? await file.length() : 0;
    if (length < PackedTrack.headerLength) {
      await file.writeAsBytes(PackedTrack.header(), flush: true);
      _pointCount = 0;
    } else {
      final records = _wholeRecords(length);
      final aligned =
          PackedTrack.headerLength + records * PackedTrack.bytesPerPoint;
      if (aligned != length) {
        // Truncated before the appending handle is opened: an appending handle
        // keeps writing at the old end of the file and would leave a hole.
        final fixer = await file.open(mode: FileMode.writeOnlyAppend);
        await fixer.truncate(aligned);
        await fixer.close();
      }
      _pointCount = records;
    }
    _handle = await file.open(mode: FileMode.append);
    _sinceFlush = 0;
    _lastFlush = _clock();
  }

  /// Appends [point], flushing when the budget is used up.
  Future<void> append(TrackPoint point) => _enqueue(() async {
    final handle = _handle;
    if (handle == null) return;
    await handle.writeFrom(PackedTrack.encodePoint(point));
    _pointCount++;
    _sinceFlush++;
    final last = _lastFlush ?? _clock();
    if (_sinceFlush >= flushEveryPoints ||
        _clock().difference(last) >= flushInterval) {
      await _flushNow();
    }
  });

  /// Forces everything written so far out to disk.
  Future<void> flush() => _enqueue(_flushNow);

  /// Flushes and closes the file.
  Future<void> close() => _enqueue(() async {
    final handle = _handle;
    if (handle == null) return;
    _handle = null;
    await handle.flush();
    await handle.close();
  });

  /// Every whole record in the file; a partial trailing record is ignored.
  Future<List<TrackPoint>> readPoints() => readJournalPoints(file);

  /// Deletes the file, closing it first when it is still open.
  Future<void> delete() async {
    await close();
    if (await file.exists()) await file.delete();
    _pointCount = 0;
  }

  Future<void> _flushNow() async {
    await _handle?.flush();
    _sinceFlush = 0;
    _lastFlush = _clock();
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }

  static int _wholeRecords(int length) =>
      (length - PackedTrack.headerLength) ~/ PackedTrack.bytesPerPoint;
}

/// Reads the whole records of a journal file; a missing or headerless file
/// reads as no points, and a trailing partial record is ignored.
Future<List<TrackPoint>> readJournalPoints(File file) async {
  if (!await file.exists()) return const <TrackPoint>[];
  final bytes = await file.readAsBytes();
  if (bytes.length <= PackedTrack.headerLength) return const <TrackPoint>[];
  try {
    return PackedTrack.decodePoints(bytes);
  } on FormatException {
    return const <TrackPoint>[];
  }
}

/// The recording directory: the journals and the state file.
///
/// The directory is a constructor argument rather than a call to
/// `path_provider`, so every test runs on a temporary directory.
class RecordingStore {
  /// Creates a store over [directory].
  RecordingStore(this.directory, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Opens the real store under `<appSupport>/recording`.
  static Future<RecordingStore> open() async {
    final base = await getApplicationSupportDirectory();
    return RecordingStore(Directory(p.join(base.path, 'recording')));
  }

  /// Where the journals and the state file live.
  final Directory directory;

  final DateTime Function() _clock;

  /// The state file.
  File get stateFile => File(p.join(directory.path, recordingStateFileName));

  /// The journal of the ride with [rideId].
  File journalFile(String rideId) =>
      File(p.join(directory.path, '$rideId$recordingJournalExtension'));

  /// A journal writer for the ride with [rideId]; still has to be opened.
  RecordingJournal openJournal(String rideId) =>
      RecordingJournal(file: journalFile(rideId), clock: _clock);

  /// Creates the directory when it does not exist yet.
  Future<void> ensureDirectory() => directory.create(recursive: true);

  /// The state of an unfinished recording, or `null` when there is none.
  ///
  /// An unreadable file is treated as "no recording": a ride that cannot be
  /// identified cannot be resumed either, and refusing to start a new one
  /// would be worse.
  Future<RecordingState?> readState() async {
    final file = stateFile;
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      return RecordingState.fromJson(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Writes [state], creating the directory if needed.
  ///
  /// The file is written to a temporary name and renamed, so a kill in the
  /// middle never leaves half a JSON document behind.
  int _stateWrites = 0;

  Future<void> writeState(RecordingState state) async {
    await ensureDirectory();
    // A unique temporary name per write, so two writers can never rename
    // each other's file away.
    final temporary = File('${stateFile.path}.${_stateWrites++}.tmp');
    await temporary.writeAsString(jsonEncode(state.toJson()), flush: true);
    await temporary.rename(stateFile.path);
  }

  /// Forgets the current recording.
  Future<void> clearState() async {
    final file = stateFile;
    if (await file.exists()) await file.delete();
  }

  /// The points already journalled for [rideId].
  Future<List<TrackPoint>> readJournal(String rideId) =>
      readJournalPoints(journalFile(rideId));

  /// Deletes the journal of [rideId].
  Future<void> deleteJournal(String rideId) async {
    final file = journalFile(rideId);
    if (await file.exists()) await file.delete();
  }
}
