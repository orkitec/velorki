// Sampling CPU profile of `tool/bench.dart` through the VM service (no
// packages: a raw JSON-RPC WebSocket from `dart:io`), JIT or AOT.
//
//   dart run tool/profile.dart [--aot] [--top N] [--period us]
//       [--callers <name substring>]... -- <bench args>
//
// JIT: runs `dart --enable-vm-service --profiler tool/bench.dart <args>`.
// AOT: `dart compile aot-snapshot tool/bench.dart` into a temp dir and runs it
// with the SDK's `dartaotruntime` (found next to the `dart` binary), which is
// what a release app runs. Prints the functions with the most exclusive and
// inclusive samples (`getCpuSamples` of the main isolate, paused at exit).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  var aot = false;
  var top = 40;
  var period = 250;
  final callers = <String>[];
  final benchArgs = <String>['--no-worker'];
  var i = 0;
  for (; i < args.length; i++) {
    final a = args[i];
    if (a == '--') {
      benchArgs.addAll(args.sublist(i + 1));
      break;
    } else if (a == '--aot') {
      aot = true;
    } else if (a == '--top') {
      top = int.parse(args[++i]);
    } else if (a == '--period') {
      period = int.parse(args[++i]);
    } else if (a == '--callers') {
      callers.add(args[++i]);
    } else {
      benchArgs.add(a);
    }
  }

  final dartExe = File(Platform.resolvedExecutable);
  final sdkBin = dartExe.parent.path;
  final vmFlags = <String>[
    '--enable-vm-service=0',
    '--profiler',
    '--profile-period=$period',
    '--sample-buffer-duration=600',
    '--pause-isolates-on-exit',
    '--disable-service-auth-codes',
  ];
  late Process process;
  Directory? tmp;
  if (aot) {
    tmp = Directory.systemTemp.createTempSync('brouter_profile');
    final snapshot = '${tmp.path}/bench.aot';
    stderr.writeln('compiling AOT snapshot...');
    final c = await Process.run(dartExe.path, [
      'compile',
      'aot-snapshot',
      'tool/bench.dart',
      '-o',
      snapshot,
    ]);
    if (c.exitCode != 0) {
      stderr.writeln(c.stdout);
      stderr.writeln(c.stderr);
      exit(1);
    }
    process = await Process.start('$sdkBin/dartaotruntime', [
      ...vmFlags,
      snapshot,
      ...benchArgs,
    ]);
  } else {
    process = await Process.start(dartExe.path, [
      ...vmFlags,
      'tool/bench.dart',
      ...benchArgs,
    ]);
  }

  final uriCompleter = Completer<Uri>();
  process.stderr.transform(utf8.decoder).listen(stderr.write);
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      final m = RegExp(
        r'Dart VM service is listening on (http://\S+)',
      ).firstMatch(line);
      if (m != null && !uriCompleter.isCompleted) {
        uriCompleter.complete(Uri.parse(m.group(1)!));
        return;
      }
      stdout.writeln(line);
    },
  );
  final http = await uriCompleter.future;
  final ws = await WebSocket.connect(
    'ws://${http.host}:${http.port}${http.path}ws',
  );
  var nextId = 1;
  final pending = <int, Completer<Map<String, dynamic>>>{};
  ws.listen((data) {
    final m = jsonDecode(data as String) as Map<String, dynamic>;
    final id = m['id'];
    if (id != null) {
      final c = pending.remove(int.parse(id as String));
      if (c == null) return;
      if (m['error'] != null) {
        c.completeError(StateError(jsonEncode(m['error'])));
      } else {
        c.complete(m['result'] as Map<String, dynamic>);
      }
    }
  });
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    final id = nextId++;
    final c = Completer<Map<String, dynamic>>();
    pending[id] = c;
    ws.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': '$id',
        'method': method,
        'params': params,
      }),
    );
    return c.future;
  }

  // the main isolate
  String? isolateId;
  while (isolateId == null) {
    final vm = await call('getVM');
    for (final iso in (vm['isolates'] as List).cast<Map<String, dynamic>>()) {
      if (iso['name'] == 'main') isolateId = iso['id'] as String;
    }
    if (isolateId == null) await Future<void>.delayed(Duration(milliseconds: 100));
  }
  // wait for PauseExit
  for (;;) {
    final iso = await call('getIsolate', {'isolateId': isolateId});
    final pause = iso['pauseEvent'] as Map<String, dynamic>?;
    if (pause != null && pause['kind'] == 'PauseExit') break;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  final samples = await call('getCpuSamples', {
    'isolateId': isolateId,
    'timeOriginMicros': 0,
    'timeExtentMicros': 1 << 60,
  });
  final total = samples['sampleCount'] as int;
  final functions = (samples['functions'] as List).cast<Map<String, dynamic>>();
  String nameOf(Map<String, dynamic> f) {
    final fn = f['function'] as Map<String, dynamic>;
    final owner = fn['owner'] as Map<String, dynamic>?;
    final ownerName = owner == null ? '' : (owner['name'] as String? ?? '');
    final name = fn['name'] as String;
    if (ownerName.isEmpty || owner!['type'] == '@Library') return name;
    return '$ownerName.$name';
  }

  final names = [for (final f in functions) nameOf(f)];
  final rows = [
    for (var i = 0; i < functions.length; i++)
      (
        name: names[i],
        excl: functions[i]['exclusiveTicks'] as int,
        incl: functions[i]['inclusiveTicks'] as int,
      ),
  ];
  String pct(int n) => '${(100.0 * n / total).toStringAsFixed(1)}%';
  stdout.writeln();
  stdout.writeln(
    '${aot ? 'AOT' : 'JIT'} profile: $total samples, period $period us',
  );
  stdout.writeln();
  stdout.writeln('Top $top by exclusive (self) time:');
  rows.sort((a, b) => b.excl.compareTo(a.excl));
  for (final r in rows.take(top)) {
    stdout.writeln(
      '${pct(r.excl).padLeft(6)} ${pct(r.incl).padLeft(7)} incl  ${r.name}',
    );
  }
  stdout.writeln();
  stdout.writeln('Top $top by inclusive time:');
  rows.sort((a, b) => b.incl.compareTo(a.incl));
  for (final r in rows.take(top)) {
    stdout.writeln(
      '${pct(r.incl).padLeft(6)} ${pct(r.excl).padLeft(7)} self  ${r.name}',
    );
  }

  // caller breakdown for the functions matching --callers (leaf frames only)
  final sampleList = (samples['samples'] as List).cast<Map<String, dynamic>>();
  for (final pattern in callers) {
    final counts = <String, int>{};
    var matched = 0;
    for (final s in sampleList) {
      final stack = (s['stack'] as List).cast<int>();
      if (stack.isEmpty) continue;
      if (!names[stack[0]].contains(pattern)) continue;
      matched++;
      final chain = [
        for (var d = 1; d < stack.length && d <= 3; d++) names[stack[d]],
      ].join(' <- ');
      counts[chain] = (counts[chain] ?? 0) + 1;
    }
    stdout.writeln();
    stdout.writeln(
      'Callers of leaf frames matching "$pattern" ($matched samples, ${pct(matched)}):',
    );
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted.take(25)) {
      stdout.writeln('${pct(e.value).padLeft(6)}  ${e.key}');
    }
  }

  await call('resume', {'isolateId': isolateId});
  await process.exitCode;
  await ws.close();
  tmp?.deleteSync(recursive: true);
}
