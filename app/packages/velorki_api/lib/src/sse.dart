import 'dart:async';
import 'dart:convert';

/// One dispatched Server-Sent Event.
///
/// Produced by [SseDecoder] / [parseSse] from a `text/event-stream` body.
class SseEvent {
  /// Creates an event.
  const SseEvent({this.name = 'message', this.data = '', this.id, this.retry});

  /// The event name from the `event:` field, or `message` when absent —
  /// the default event type mandated by the SSE specification.
  final String name;

  /// The `data:` payload. Several `data:` lines in one block are joined with
  /// a newline, in the order they appeared.
  final String data;

  /// The last `id:` field seen, when the stream sent one.
  final String? id;

  /// The `retry:` reconnection time in milliseconds, when the stream sent one.
  final int? retry;

  @override
  bool operator ==(Object other) =>
      other is SseEvent &&
      other.name == name &&
      other.data == data &&
      other.id == id &&
      other.retry == retry;

  @override
  int get hashCode => Object.hash(name, data, id, retry);

  @override
  String toString() =>
      'SseEvent($name, data: ${jsonEncode(data)}'
      '${id == null ? '' : ', id: $id'}'
      '${retry == null ? '' : ', retry: $retry'})';
}

/// Turns a raw `text/event-stream` byte stream into [SseEvent]s.
///
/// Implements the parsing rules of the SSE specification:
///
/// * lines end with LF, CRLF or a bare CR, and a chunk boundary may fall
///   anywhere, including between the CR and the LF of a CRLF pair;
/// * a line starting with `:` is a comment and is ignored;
/// * a line without a `:` is a field with an empty value;
/// * exactly one space after the field's `:` is stripped;
/// * `data:` lines accumulate and are joined with a newline;
/// * a blank line dispatches the accumulated event and resets the buffers;
/// * an absent `event:` field means the event name `message`;
/// * a block that accumulated no `data:` line is not dispatched.
///
/// Two deliberate liberties are taken with the specification, both in the
/// direction of losing less data:
///
/// * when the stream ends in the middle of a line, that partial line is still
///   treated as a complete line rather than discarded;
/// * when the stream ends with an undispatched block, that block is
///   dispatched rather than discarded — servers that close without a final
///   blank line are common.
///
/// The decoder keeps no state between `bind` calls, so a `const` instance can
/// be shared.
class SseDecoder extends StreamTransformerBase<List<int>, SseEvent> {
  /// Creates a decoder.
  const SseDecoder();

  @override
  Stream<SseEvent> bind(Stream<List<int>> stream) =>
      bindText(const Utf8Decoder(allowMalformed: true).bind(stream));

  /// Same as [bind], but for a body that has already been decoded to text.
  ///
  /// Useful for tests and for transports that hand over strings. The chunks
  /// may still split lines at any point.
  Stream<SseEvent> bindText(Stream<String> stream) async* {
    final splitter = _LineSplitter();
    final block = _Block();

    await for (final chunk in stream) {
      for (final line in splitter.add(chunk)) {
        final event = block.line(line);
        if (event != null) yield event;
      }
    }
    for (final line in splitter.close()) {
      final event = block.line(line);
      if (event != null) yield event;
    }
    final trailing = block.flush();
    if (trailing != null) yield trailing;
  }
}

/// Parses a `text/event-stream` body into events.
///
/// A convenience wrapper around [SseDecoder] so SSE parsing can be tested and
/// reused without any HTTP involvement.
Stream<SseEvent> parseSse(Stream<List<int>> body) =>
    const SseDecoder().bind(body);

/// Parses an already decoded `text/event-stream` body into events.
Stream<SseEvent> parseSseText(Stream<String> body) =>
    const SseDecoder().bindText(body);

/// Splits an incrementally arriving text stream into lines.
///
/// Handles LF, CRLF and a bare CR, and carries the "the previous chunk ended
/// with a CR" state across chunk boundaries so a CRLF split by the boundary
/// does not produce a spurious empty line.
class _LineSplitter {
  static const int _cr = 0x0d;
  static const int _lf = 0x0a;

  final StringBuffer _pending = StringBuffer();
  bool _afterCr = false;

  /// Feeds one chunk and yields every complete line it contained.
  Iterable<String> add(String chunk) sync* {
    for (var i = 0; i < chunk.length; i++) {
      final code = chunk.codeUnitAt(i);
      if (code == _lf) {
        if (_afterCr) {
          // The line was already emitted when the CR was seen.
          _afterCr = false;
          continue;
        }
        yield _take();
      } else if (code == _cr) {
        // A bare CR terminates a line too, so emit now; a LF that follows is
        // swallowed by the branch above.
        yield _take();
        _afterCr = true;
      } else {
        _afterCr = false;
        _pending.write(chunk[i]);
      }
    }
  }

  /// Yields whatever is left as a final, unterminated line.
  Iterable<String> close() sync* {
    _afterCr = false;
    if (_pending.isNotEmpty) yield _take();
  }

  String _take() {
    final line = _pending.toString();
    _pending.clear();
    return line;
  }
}

/// The field buffers of the event currently being accumulated.
class _Block {
  final List<String> _data = <String>[];
  String? _name;
  String? _id;
  int? _retry;
  bool _any = false;

  /// Processes one line; returns an event when the line dispatched one.
  SseEvent? line(String line) {
    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) return null; // comment

    final colon = line.indexOf(':');
    final String field;
    String value;
    if (colon < 0) {
      field = line;
      value = '';
    } else {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
    }

    switch (field) {
      case 'event':
        _name = value;
        _any = true;
      case 'data':
        _data.add(value);
        _any = true;
      case 'id':
        _id = value;
        _any = true;
      case 'retry':
        final parsed = int.tryParse(value);
        if (parsed != null) _retry = parsed;
        _any = true;
      default:
        // Unknown field names are ignored, as the spec requires.
        break;
    }
    return null;
  }

  /// Dispatches the accumulated block, if it accumulated any `data:` line.
  SseEvent? _dispatch() {
    if (_data.isEmpty) {
      _reset();
      return null;
    }
    final event = SseEvent(
      name: _name == null || _name!.isEmpty ? 'message' : _name!,
      data: _data.join('\n'),
      id: _id,
      retry: _retry,
    );
    _reset();
    return event;
  }

  /// Dispatches a block left over at end of stream, if there is one.
  SseEvent? flush() => _any ? _dispatch() : null;

  void _reset() {
    _data.clear();
    _name = null;
    _retry = null;
    _any = false;
    // `id` deliberately persists: the spec keeps the last event id across
    // events so a reconnect can resume from it.
  }
}
