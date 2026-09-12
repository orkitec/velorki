import 'dart:convert';

import 'package:test/test.dart';
import 'package:velorki_api/velorki_api.dart';

/// Feeds [text] as raw bytes in chunks of exactly [size] characters, so line
/// boundaries fall inside chunks in a way the decoder has to survive.
Stream<List<int>> chunked(String text, int size) async* {
  for (var i = 0; i < text.length; i += size) {
    final end = i + size > text.length ? text.length : i + size;
    yield utf8.encode(text.substring(i, end));
  }
}

/// Feeds the literal chunks given, so a boundary can be placed deliberately.
Stream<List<int>> chunks(List<String> parts) async* {
  for (final part in parts) {
    yield utf8.encode(part);
  }
}

void main() {
  const crlf = '\r\n';

  group('parseSse', () {
    // A realistic /ai/plan body: the relay's opening comment frame, a
    // route_request, text deltas, a multi-line data payload and a done event.
    const body =
        ': open\n'
        '\n'
        'event: route_request\n'
        'data: {"distance_km":62.5,"loop":true,'
        '"start":{"use_current":true},"surface":"mixed","hills":"seek",'
        '"traffic_tolerance":"low","profile_hint":"trekking"}\n'
        '\n'
        'event: text\n'
        'data: {"delta":"A quiet loop "}\n'
        '\n'
        'event: text\n'
        'data: {"delta":"through the Kaiserstuhl."}\n'
        '\n'
        'event: text\n'
        'data: first line\n'
        'data: second line\n'
        '\n'
        ': keep-alive\n'
        '\n'
        'event: done\n'
        'data: {"usage":{"in":1200,"out":310},"model":"claude-sonnet"}\n'
        '\n';

    test('parses a full stream delivered in one chunk', () async {
      final events = await parseSse(chunks([body])).toList();
      expect(events.map((e) => e.name), <String>[
        'route_request',
        'text',
        'text',
        'text',
        'done',
      ]);
      expect(events[2].data, '{"delta":"through the Kaiserstuhl."}');
      // Several data: lines in one block are joined with a newline.
      expect(events[3].data, 'first line\nsecond line');
    });

    test('is insensitive to where the chunk boundaries fall', () async {
      final reference = await parseSse(chunks([body])).toList();
      for (final size in <int>[1, 2, 3, 7, 13, 64, 500]) {
        final events = await parseSse(chunked(body, size)).toList();
        expect(events, reference, reason: 'chunk size $size');
      }
    });

    test(
      'handles CRLF line endings and a boundary between CR and LF',
      () async {
        final crlfBody = body.replaceAll('\n', crlf);
        final events = await parseSse(chunked(crlfBody, 1)).toList();
        expect(events.length, 5);
        expect(events.first.name, 'route_request');
        expect(events[3].data, 'first line\nsecond line');
        expect(events.last.name, 'done');
      },
    );

    test('survives a chunk boundary in the middle of a line', () async {
      final events = await parseSse(
        chunks(<String>[
          'event: te',
          'xt\ndata: {"del',
          'ta":"hal',
          'f"}\n\nevent: do',
          'ne\r',
          '\ndata: {}\r\n\r\n',
        ]),
      ).toList();
      expect(events.map((e) => e.name), <String>['text', 'done']);
      expect(events.first.data, '{"delta":"half"}');
    });

    test('ignores comment lines and blank blocks', () async {
      final events = await parseSse(
        chunks(<String>[
          ': a comment\n:another\n\n\n\nevent: text\ndata: hi\n\n',
        ]),
      ).toList();
      expect(events.length, 1);
      expect(events.single.data, 'hi');
    });

    test('an absent event: field means the default name message', () async {
      final events = await parseSse(chunks(['data: bare\n\n'])).toList();
      expect(events.single.name, 'message');
      expect(events.single.data, 'bare');
    });

    test('strips exactly one space after the colon', () async {
      final events = await parseSse(chunks(['data:no space\n\ndata:  two\n\n']))
          .toList();
      expect(events[0].data, 'no space');
      expect(events[1].data, ' two');
    });

    test('a field line without a colon has an empty value', () async {
      final events = await parseSse(chunks(['data\ndata: x\n\n'])).toList();
      expect(events.single.data, '\nx');
    });

    test('carries id and retry, and keeps the id across events', () async {
      final events = await parseSse(
        chunks(<String>['id: 7\nretry: 2500\ndata: one\n\ndata: two\n\n']),
      ).toList();
      expect(events[0].id, '7');
      expect(events[0].retry, 2500);
      expect(events[1].id, '7', reason: 'the last event id persists');
      expect(events[1].retry, isNull);
    });

    test('a block with no data: line is not dispatched', () async {
      final events = await parseSse(
        chunks(['event: ping\n\nevent: text\ndata: x\n\n']),
      ).toList();
      expect(events.single.name, 'text');
    });

    test('dispatches a trailing block that has no final blank line', () async {
      final events = await parseSse(
        chunks(['event: done\ndata: {"model":"m"}']),
      ).toList();
      expect(events.single.name, 'done');
      expect(events.single.data, '{"model":"m"}');
    });

    test('an empty body yields no events', () async {
      expect(await parseSse(chunks(<String>[])).toList(), isEmpty);
      expect(await parseSse(chunks(<String>[''])).toList(), isEmpty);
    });

    test('decodes multi-byte UTF-8 split across a chunk boundary', () async {
      final bytes = utf8.encode('data: Höhenmeter über München\n\n');
      // Split inside the two-byte sequence of the first umlaut.
      final cut = utf8.encode('data: H').length + 1;
      final events = await parseSse(() async* {
        yield bytes.sublist(0, cut);
        yield bytes.sublist(cut);
      }()).toList();
      expect(events.single.data, 'Höhenmeter über München');
    });

    test('parseSseText decodes an already-decoded body', () async {
      final events = await parseSseText(
        Stream<String>.fromIterable(<String>['event: text\n', 'data: x\n\n']),
      ).toList();
      expect(events.single, const SseEvent(name: 'text', data: 'x'));
    });
  });
}
