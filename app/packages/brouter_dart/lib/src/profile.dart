/// Compile-time profiling switch for track R5: `dart -DBROUTER_PROFILE=true`
/// (or `dart compile exe -DBROUTER_PROFILE=true`) turns the counters below
/// on; otherwise every `if (kProfile)` block is dead code.
library;

const bool kProfile = bool.fromEnvironment('BROUTER_PROFILE');

/// Stopwatch counters around the hot phases of a route.
class Prof {
  Prof._();

  static final Stopwatch read = Stopwatch();
  static int reads = 0;
  static int readBytes = 0;
  static int readHits = 0;

  static final Stopwatch weave = Stopwatch();
  static int weaves = 0;

  static final Stopwatch collect = Stopwatch();
  static int collects = 0;

  static final Stopwatch compile = Stopwatch();
  static final Stopwatch match = Stopwatch();
  static final Stopwatch format = Stopwatch();

  static final Stopwatch createPath = Stopwatch();
  static int paths = 0;

  static int evalRequests = 0;
  static int evalMisses = 0;
  static int evalSame = 0;

  static int expansions = 0;
  static int segments = 0;

  static void reset() {
    read.reset();
    reads = 0;
    readBytes = 0;
    readHits = 0;
    weave.reset();
    weaves = 0;
    collect.reset();
    collects = 0;
    compile.reset();
    match.reset();
    format.reset();
    createPath.reset();
    paths = 0;
    evalRequests = 0;
    evalMisses = 0;
    evalSame = 0;
    expansions = 0;
    segments = 0;
  }

  static String report(int totalMicros) {
    String ms(Stopwatch sw) =>
        '${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms '
        '(${(100 * sw.elapsedMicroseconds / totalMicros).toStringAsFixed(0)}%)';
    return [
      '  total ${(totalMicros / 1000).toStringAsFixed(1)} ms, '
          '$segments findTrack passes, $expansions expansions',
      '  cell reads: $reads (${(readBytes / 1048576).toStringAsFixed(1)} MB, '
          '$readHits LRU hits) ${ms(read)}',
      '  direct weaving: $weaves cells ${ms(weave)}',
      '  createPath: $paths ${ms(createPath)}',
      '  expression cache: $evalRequests requests, $evalMisses misses, '
          '$evalSame same-array hits',
      '  collectOutreachers: $collects ${ms(collect)}',
      '  matchWaypoints ${ms(match)}, compileTrack ${ms(compile)}, '
          'format ${ms(format)}',
    ].join('\n');
  }
}
