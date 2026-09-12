// Port of btools.expressions.BExpressionContext (BRouter v1.7.10).
//
// context for simple expression
// context means:
// - the local variables
// - the local variable names
// - the lookup-input variables

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../jfloat.dart';
import '../jvm.dart';
import '../profile.dart';
import '../util/bit_coder_context.dart';
import '../util/crc32.dart';
import '../util/i_byte_array_unifier.dart';
import '../util/lru_map.dart';
import 'b_expression.dart';
import 'b_expression_lookup_value.dart';
import 'b_expression_meta_data.dart';
import 'cache_node.dart';
import 'var_wrapper.dart';

/// Java overloads are renamed: `encode(int[])` is [encodeLookupData],
/// `decode(int[], boolean, byte[])` is [decodeInto], `evaluate(int[])` is
/// [evaluateLookupData], `getLookupValue(boolean, byte[], int)` is
/// [getLookupValueOf], `addLookupValue(String, int)` is [addLookupValueIndex]
/// and `getVariableValue(int)` is [getVariableValueByIdx]. `float` values are
/// doubles holding a float value; `variableData` is a `Float32List`, so every
/// assignment rounds like the JVM.
abstract class BExpressionContext implements IByteArrayUnifier {
  /// Create an Expression-Context for the given node
  ///
  /// [context]  global, way or node - context of that instance
  /// [hashSize] size of hashmap for result caching
  BExpressionContext(String context, int hashSize, BExpressionMetaData? meta)
    : _context = context,
      meta = meta {
    meta?.registerListener(context, this);

    if (disableExpressionCache) hashSize = 1;

    // create the expression cache
    if (hashSize > 0) {
      _cache = LruMap(4 * hashSize, hashSize);
      _resultVarCache = LruMap(4096, 4096);
    }
  }

  static const String _contextTag = '---context:';
  static const String _modelTag = '---model:';

  /// `Boolean.getBoolean("disableExpressionCache")`, read per instance in the
  /// constructor.
  static bool disableExpressionCache = false;

  /// `Boolean.getBoolean("showErrors")`.
  static bool showErrors = false;

  String _context;
  bool _inOurContext = false;
  String? _br; // the profile text being tokenised (BufferedReader upstream)
  int _brPos = 0;
  bool _readerDone = false;

  // ignore: non_constant_identifier_names
  String? _modelClass;

  final Map<String, int> _lookupNumbers = <String, int>{};
  final List<List<BExpressionLookupValue>> _lookupValues =
      <List<BExpressionLookupValue>>[];
  final List<String> _lookupNames = <String>[];
  final List<Int32List> _lookupHistograms = <Int32List>[];
  List<bool>? _lookupIdxUsed;

  bool _lookupDataFrozen = false;

  Int32List _lookupData = Int32List(0);

  final Uint8List _abBuf = Uint8List(256);
  late final BitCoderContext _ctxEndode = BitCoderContext(_abBuf);
  final BitCoderContext _ctxDecode = BitCoderContext(Uint8List(0));

  final Map<String, int> _variableNumbers = <String, int>{};

  List<BExpression?>? lastAssignedExpression = <BExpression?>[];
  bool skipConstantExpressionOptimizations = false;
  int expressionNodeCount = 0;

  Float32List? _variableData;

  // hash-cache for function results
  final CacheNode _probeCacheNode = CacheNode();
  LruMap? _cache;

  final VarWrapper _probeVarSet = VarWrapper();
  LruMap? _resultVarCache;

  List<BExpression>? _expressionList;

  int _minWriteIdx = 0;

  // build-in variable indexes for fast access
  List<int>? _buildInVariableIdx;
  int _nBuildInVars = 0;

  Float32List? _currentVars;
  int _currentVarOffset = 0;

  BExpressionContext? _foreignContext;

  List<int> noStartWays = <int>[];

  void setInverseVars() {
    _currentVarOffset = _nBuildInVars;
  }

  List<String> getBuildInVariableNames();

  double getBuildInVariable(int idx) {
    return _currentVars![idx + _currentVarOffset];
  }

  int _linenr = 0;

  final BExpressionMetaData? meta;
  bool _lookupDataValid = false;

  /// `_modelClass` (the `---model:` tag of the profile).
  String? get modelClass => _modelClass;

  /// The context name ("global", "way" or "node").
  String get context => _context;

  /// The number of lookup names known to this context.
  int get lookupCount => _lookupValues.length;

  /// The lookup name at index [inum].
  String lookupName(int inum) => _lookupNames[inum];

  /// The values (primary names) of the lookup at index [inum].
  List<String> lookupValueNames(int inum) => [
    for (final v in _lookupValues[inum]) v.value,
  ];

  /// The variables known to this context, in index order.
  List<String> variableNames() {
    final names = List<String>.filled(_variableNumbers.length, '');
    for (final e in _variableNumbers.entries) {
      names[e.value] = e.key;
    }
    return names;
  }

  /// encode internal lookup data to a byte array
  Uint8List? encode() {
    if (!_lookupDataValid) {
      throw ArgumentError('internal error: encoding undefined data?');
    }
    return encodeLookupData(_lookupData);
  }

  /// `encode(int[] ld)`.
  Uint8List? encodeLookupData(List<int> ld) {
    final ctx = _ctxEndode;
    ctx.reset();

    var skippedTags = 0;
    var nonNullTags = 0;

    // (skip first bit ("reversedirection") )

    // all others are generic
    for (var inum = 1; inum < _lookupValues.length; inum++) {
      // loop over lookup names
      final d = ld[inum];
      if (d == 0) {
        skippedTags++;
        continue;
      }
      ctx.encodeVarBits(skippedTags + 1);
      nonNullTags++;
      skippedTags = 0;

      // 0 excluded already, 1 (=unknown) we rotate up to 8
      // to have the good code space for the popular values
      final dd = d < 2 ? 7 : (d < 9 ? d - 2 : d - 1);
      ctx.encodeVarBits(dd);
    }
    ctx.encodeVarBits(0);

    if (nonNullTags == 0) return null;

    final len = ctx.closeAndGetEncodedLength();
    final ab = Uint8List(len);
    ab.setRange(0, len, _abBuf);

    // crosscheck: decode and compare
    final ld2 = Int32List(_lookupValues.length);
    decodeInto(ld2, false, ab);
    for (var inum = 1; inum < _lookupValues.length; inum++) {
      // loop over lookup names (except reverse dir)
      if (ld2[inum] != ld[inum]) {
        throw StateError(
          'assertion failed encoding inum=$inum val=${ld[inum]} ${getKeyValueDescription(false, ab)}',
        );
      }
    }

    return ab;
  }

  /// decode byte array to internal lookup data
  void decode(Uint8List ab) {
    decodeInto(_lookupData, false, ab);
    _lookupDataValid = true;
  }

  /// decode a byte-array into a lookup data array
  ///
  /// `decode(int[] ld, boolean inverseDirection, byte[] ab)`.
  void decodeInto(List<int> ld, bool inverseDirection, Uint8List ab) {
    final ctx = _ctxDecode;
    ctx.reset(ab);

    // start with first bit hardwired ("reversedirection")
    ld[0] = inverseDirection ? 2 : 0;

    // all others are generic
    var inum = 1;
    for (;;) {
      var delta = ctx.decodeVarBits();
      if (delta == 0) break;
      if (inum + delta > ld.length) break; // higher minor version is o.k.

      while (delta-- > 1) {
        ld[inum++] = 0;
      }

      // see encoder for value rotation
      final dd = ctx.decodeVarBits();
      var d = dd == 7 ? 1 : (dd < 7 ? dd + 2 : dd + 1);
      if (d >= _lookupValues[inum].length && d < 1000) {
        d = 1; // map out-of-range to unknown
      }
      ld[inum++] = d;
    }
    while (inum < ld.length) {
      ld[inum++] = 0;
    }
  }

  /// `Float.toString((val - 1000) / 100f)`.
  static String _numericValueString(int val) =>
      javaFloatToString(f32(f32((val - 1000).toDouble()) / 100.0));

  String getKeyValueDescription(bool inverseDirection, Uint8List ab) {
    final sb = StringBuffer();
    decodeInto(_lookupData, inverseDirection, ab);
    for (var inum = 0; inum < _lookupValues.length; inum++) {
      // loop over lookup names
      final va = _lookupValues[inum];
      final val = _lookupData[inum];
      final value = val >= 1000 ? _numericValueString(val) : va[val].toString();
      if (value.isNotEmpty) {
        if (sb.length > 0) sb.write(' ');
        sb.write('${_lookupNames[inum]}=$value');
      }
    }
    return sb.toString();
  }

  List<String> getKeyValueList(bool inverseDirection, Uint8List ab) {
    final res = <String>[];
    decodeInto(_lookupData, inverseDirection, ab);
    for (var inum = 0; inum < _lookupValues.length; inum++) {
      // loop over lookup names
      final va = _lookupValues[inum];
      final val = _lookupData[inum];
      // no negative values
      final value = val >= 1000 ? _numericValueString(val) : va[val].toString();
      if (value.isNotEmpty) {
        res.add(_lookupNames[inum]);
        res.add(value);
      }
    }
    return res;
  }

  int getLookupKey(String name) {
    return _lookupNumbers[name] ?? -1;
  }

  double getLookupValue(int key) {
    var res = 0.0;
    final val = _lookupData[key];
    if (val == 0) return double.nan;
    if (val < 900) {
      try {
        final va = _lookupValues[key];
        final sval = va[val].toString();
        res = javaParseFloat(sval);
      } on NumberFormatException {
        res = 0.0;
      }
    } else {
      res = f32(f32((val - 1000).toDouble()) / 100.0);
    }
    return res;
  }

  /// `getLookupValue(boolean inverseDirection, byte[] ab, int key)`.
  double getLookupValueOf(bool inverseDirection, Uint8List ab, int key) {
    var res = 0.0;
    decodeInto(_lookupData, inverseDirection, ab);
    final val = _lookupData[key];
    if (val == 0) return double.nan;
    res = f32(f32((val - 1000).toDouble()) / 100.0);
    return res;
  }

  int _parsedLines = 0;
  bool _fixTagsWritten = false;

  void parseMetaLine(String line) {
    _parsedLines++;
    // StringTokenizer(line, " ")
    final tk = line.split(' ').where((t) => t.isNotEmpty).iterator;
    if (!tk.moveNext()) throw StateError('NoSuchElementException');
    var name = tk.current;
    if (!tk.moveNext()) throw StateError('NoSuchElementException');
    final value = tk.current;
    final idx = name.indexOf(';');
    if (idx >= 0) name = name.substring(0, idx);

    if (!_fixTagsWritten) {
      _fixTagsWritten = true;
      if ('way' == _context) {
        addLookupValue('reversedirection', 'yes', null);
      } else if ('node' == _context) {
        addLookupValue('nodeaccessgranted', 'yes', null);
      }
    }
    if ('reversedirection' == name) return; // this is hardcoded
    if ('nodeaccessgranted' == name) return; // this is hardcoded
    final newValue = addLookupValue(name, value, null);

    // add aliases
    while (newValue != null && tk.moveNext()) {
      newValue.addAlias(tk.current);
    }
  }

  void finishMetaParsing() {
    if (_parsedLines == 0 && 'global' != _context) {
      throw ArgumentError(
        'lookup table does not contain data for context $_context (old version?)',
      );
    }

    // post-process metadata:
    _lookupDataFrozen = true;

    _lookupIdxUsed = List<bool>.filled(_lookupValues.length, false);
  }

  /// `evaluate(int[] lookupData2)`.
  void evaluateLookupData(Int32List lookupData2) {
    _lookupData = lookupData2;
    _evaluate();
  }

  void _evaluate() {
    final list = _expressionList!;
    final n = list.length;
    for (var expidx = 0; expidx < n; expidx++) {
      list[expidx].evaluate(this);
    }
  }

  int _requests = 0;
  int _requests2 = 0;
  int _cachemisses = 0;

  String cacheStats() {
    return 'requests=$_requests requests2=$_requests2 cachemisses=$_cachemisses';
  }

  CacheNode _lastCacheNode = CacheNode();

  @override
  Uint8List unify(Uint8List ab, int offset, int len) {
    _probeCacheNode.ab = null; // crc based cache lookup only
    _probeCacheNode.hash = Crc32.crc(ab, offset, len);

    var cn = _cache!.get(_probeCacheNode) as CacheNode?;
    if (cn != null) {
      final cab = cn.ab!;
      if (cab.length == len) {
        for (var i = 0; i < len; i++) {
          if (cab[i] != ab[i + offset]) {
            cn = null;
            break;
          }
        }
        if (cn != null) {
          _lastCacheNode = cn;
          return cn.ab!;
        }
      }
    }
    final nab = Uint8List(len);
    nab.setRange(0, len, ab, offset);
    return nab;
  }

  /// `evaluate(boolean inverseDirection, byte[] ab)`.
  void evaluate(bool inverseDirection, Uint8List ab) {
    _requests++;
    if (kProfile) Prof.evalRequests++;
    _lookupDataValid = false; // this is an assertion for a nasty pifall

    final cache = _cache;
    if (cache == null) {
      decodeInto(_lookupData, inverseDirection, ab);
      if (_currentVars == null || _currentVars!.length != _nBuildInVars) {
        _currentVars = Float32List(_nBuildInVars);
      }
      _evaluateInto(_currentVars!, 0);
      _currentVarOffset = 0;
      return;
    }

    CacheNode? cn;
    if (identical(_lastCacheNode.ab, ab)) {
      cn = _lastCacheNode;
    } else {
      _probeCacheNode.ab = ab;
      _probeCacheNode.hash = Crc32.crc(ab, 0, ab.length);
      cn = cache.get(_probeCacheNode) as CacheNode?;
    }

    if (cn == null) {
      _cachemisses++;
      if (kProfile) Prof.evalMisses++;

      cn = cache.removeLru() as CacheNode?;
      cn ??= CacheNode();
      cn.hash = _probeCacheNode.hash;
      cn.ab = ab;
      cache.put(cn);

      _probeVarSet.vars ??= Float32List(2 * _nBuildInVars);

      // forward direction
      decodeInto(_lookupData, false, ab);
      _evaluateInto(_probeVarSet.vars!, 0);

      // inverse direction
      _lookupData[0] = 2; // inverse shortcut: reuse decoding
      _evaluateInto(_probeVarSet.vars!, _nBuildInVars);

      _probeVarSet.hash = arraysHashCodeFloat(_probeVarSet.vars!);

      // unify the result variable set
      var vw = _resultVarCache!.get(_probeVarSet) as VarWrapper?;
      if (vw == null) {
        vw = _resultVarCache!.removeLru() as VarWrapper?;
        vw ??= VarWrapper();
        vw.hash = _probeVarSet.hash;
        vw.vars = _probeVarSet.vars;
        _probeVarSet.vars = null;
        _resultVarCache!.put(vw);
      }
      cn.vars = vw.vars;
    } else {
      if (identical(ab, cn.ab)) {
        _requests2++;
        if (kProfile) Prof.evalSame++;
      }

      cache.touch(cn);
    }

    _currentVars = cn.vars;
    _currentVarOffset = inverseDirection ? _nBuildInVars : 0;
  }

  void _evaluateInto(Float32List vars, int offset) {
    _evaluate();
    final variableData = _variableData!;
    final buildInVariableIdx = _buildInVariableIdx!;
    for (var vi = 0; vi < _nBuildInVars; vi++) {
      final idx = buildInVariableIdx[vi];
      vars[vi + offset] = idx == -1 ? 0.0 : variableData[idx];
    }
  }

  /// `dumpStatistics()`: the lines upstream prints to `System.out`.
  List<String> dumpStatistics() {
    final out = <String>[];
    final counts = <String, String>{};
    // first count
    for (final name in _lookupNumbers.keys) {
      var cnt = 0;
      final inum = _lookupNumbers[name]!;
      final histo = _lookupHistograms[inum];
      for (var i = 2; i < histo.length; i++) {
        cnt += histo[i];
      }
      counts['${1000000000 + cnt}_$name'] = name;
    }

    while (counts.isNotEmpty) {
      final keys = counts.keys.toList()..sort();
      final key = keys.last;
      final name = counts[key]!;
      counts.remove(key);
      final inum = _lookupNumbers[name]!;
      final values = _lookupValues[inum];
      final histo = _lookupHistograms[inum];
      if (values.length == 1000) continue;
      final svalues = List<String>.filled(values.length, '');
      for (var i = 0; i < values.length; i++) {
        var scnt = '0000000000${histo[i]}';
        scnt = scnt.substring(scnt.length - 10);
        svalues[i] = '$scnt ${values[i]}';
      }
      svalues.sort();
      for (var i = svalues.length - 1; i >= 0; i--) {
        out.add('$name;${svalues[i]}');
      }
    }
    return out;
  }

  /// Returns a new lookupData array, or null if no metadata defined
  Int32List? createNewLookupData() {
    if (_lookupDataFrozen) {
      return Int32List(_lookupValues.length);
    }
    return null;
  }

  /// generate random values for regression testing
  Int32List generateRandomValues(JavaRandom rnd) {
    final data = createNewLookupData()!;
    data[0] = 2 * rnd.nextInt(2); // reverse-direction = 0 or 2
    for (var inum = 1; inum < data.length; inum++) {
      final nvalues = _lookupValues[inum].length;
      data[inum] = 0;
      if (inum > 1 && rnd.nextInt(10) > 0) {
        continue; // tags other than highway only 10%
      }
      data[inum] = rnd.nextInt(nvalues);
    }
    _lookupDataValid = true;
    return data;
  }

  void assertAllVariablesEqual(BExpressionContext other) {
    final nv = _variableData!.length;
    final nv2 = other._variableData!.length;
    if (nv != nv2) throw StateError('mismatch in variable-count: $nv<->$nv2');
    for (var i = 0; i < nv; i++) {
      if (_variableData![i] != other._variableData![i]) {
        throw StateError(
          'mismatch in variable ${variableName(i)} ${javaFloatToString(_variableData![i])}<->${javaFloatToString(other._variableData![i])}'
          '\ntags = ${getKeyValueDescription(false, encode()!)}',
        );
      }
    }
  }

  String variableName(int idx) {
    for (final e in _variableNumbers.entries) {
      if (e.value == idx) {
        return e.key;
      }
    }
    throw StateError('no variable for index$idx');
  }

  /// add a new lookup-value for the given name to the given lookupData array.
  /// If no array is given (null value passed), the value is added to
  /// the context-binded array. In that case, unknown names and values are
  /// created dynamically.
  ///
  /// Returns a newly created value element, if any, to optionally add aliases
  BExpressionLookupValue? addLookupValue(
    String name,
    String value,
    List<int>? lookupData2,
  ) {
    BExpressionLookupValue? newValue;
    var num = _lookupNumbers[name];
    if (num == null) {
      if (lookupData2 != null) {
        // do not create unknown name for external data array
        return newValue;
      }

      // unknown name, create
      num = _lookupValues.length;
      _lookupNumbers[name] = num;
      _lookupNames.add(name);
      _lookupValues.add(<BExpressionLookupValue>[
        BExpressionLookupValue(''),
        BExpressionLookupValue('unknown'),
      ]);
      _lookupHistograms.add(Int32List(2));
      final ndata = Int32List(_lookupData.length + 1);
      ndata.setRange(0, _lookupData.length, _lookupData);
      _lookupData = ndata;
    }

    // look for that value
    var values = _lookupValues[num];
    var histo = _lookupHistograms[num];
    var i = 0;
    var bFoundAsterix = false;
    for (; i < values.length; i++) {
      final v = values[i];
      if (v.value == '*') bFoundAsterix = true;
      if (v.matches(value)) break;
    }
    if (i == values.length) {
      if (lookupData2 != null) {
        // do not create unknown value for external data array,
        // record as 'unknown' instead
        lookupData2[num] = 1; // 1 == unknown
        if (bFoundAsterix) {
          // found value for lookup *
          //System.out.println( "add unknown " + name + "  " + value );
          final org = value;
          try {
            // remove some unused characters
            value = value.replaceAll(',', '.');
            value = value.replaceAll('>', '');
            value = value.replaceAll('_', '');
            value = value.replaceAll(' ', '');
            value = value.replaceAll('~', '');
            value = value.replaceAll('’', "'");
            value = value.replaceAll('”', '"');
            if (value.indexOf('-') == 0) value = value.substring(1);
            if (value.contains('-')) {
              // replace eg. 1.4-1.6 m to 1.4m
              // but also 1'-6" to 1'
              // keep the unit of measure
              final tmp = value
                  .substring(value.indexOf('-') + 1)
                  .replaceAll(RegExp('[0-9.,-]'), '');
              value = value.substring(0, value.indexOf('-'));
              if (RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) value += tmp;
            }
            value = value.toLowerCase();

            // do some value conversion
            if (value.contains('ft')) {
              var feet = 0.0;
              var inch = 0;
              final sa = javaSplit(value, 'ft');
              if (sa.isNotEmpty) feet = javaParseFloat(sa[0]);
              if (sa.length == 2) {
                value = sa[1];
                if (value.indexOf('in') > 0) {
                  value = value.substring(0, value.indexOf('in'));
                }
                inch = javaParseInt(value);
                feet = f32(feet + f32(f32(inch.toDouble()) / 12.0));
              }
              value = javaFormatFixed(f32(feet * f32(0.3048)), 1);
            } else if (value.contains("'")) {
              var feet = 0.0;
              var inch = 0;
              final sa = javaSplit(value, "'");
              if (sa.isNotEmpty) feet = javaParseFloat(sa[0]);
              if (sa.length == 2) {
                value = sa[1];
                if (value.indexOf("''") > 0) {
                  value = value.substring(0, value.indexOf("''"));
                }
                if (value.indexOf('"') > 0) {
                  value = value.substring(0, value.indexOf('"'));
                }
                inch = javaParseInt(value);
                feet = f32(feet + f32(f32(inch.toDouble()) / 12.0));
              }
              value = javaFormatFixed(f32(feet * f32(0.3048)), 1);
            } else if (value.contains('in') || value.contains('"')) {
              var inch = 0.0;
              if (value.indexOf('in') > 0) {
                value = value.substring(0, value.indexOf('in'));
              }
              if (value.indexOf('"') > 0) {
                value = value.substring(0, value.indexOf('"'));
              }
              inch = javaParseFloat(value);
              value = javaFormatFixed(f32(inch * f32(0.0254)), 1);
            } else if (value.contains('feet') || value.contains('foot')) {
              var feet = 0.0;
              final s = value.substring(0, value.indexOf('f'));
              feet = javaParseFloat(s);
              value = javaFormatFixed(f32(feet * f32(0.3048)), 1);
            } else if (value.contains('fathom') || value.contains('fm')) {
              final s = value.substring(0, value.indexOf('f'));
              final fathom = javaParseFloat(s);
              value = javaFormatFixed(f32(fathom * f32(1.8288)), 1);
            } else if (value.contains('cm')) {
              final sa = javaSplit(value, 'cm');
              if (sa.isNotEmpty) value = sa[0];
              final cm = javaParseFloat(value);
              value = javaFormatFixed(f32(cm / 100.0), 1);
            } else if (value.contains('metre') || value.contains('meter')) {
              value = value.substring(0, value.indexOf('m'));
            } else if (value.contains('mph')) {
              final sa = javaSplit(value, 'mph');
              if (sa.isNotEmpty) value = sa[0];
              final mph = javaParseFloat(value);
              value = javaFormatFixed(f32(mph * f32(1.609344)), 1);
            } else if (value.contains('knot')) {
              final sa = javaSplit(value, 'knot');
              if (sa.isNotEmpty) value = sa[0];
              final nm = javaParseFloat(value);
              value = javaFormatFixed(f32(nm * f32(1.852)), 1);
            } else if (value.contains('kmh') ||
                value.contains('km/h') ||
                value.contains('kph')) {
              final sa = javaSplit(value, 'k');
              if (sa.length > 1) value = sa[0];
            } else if (value.contains('m')) {
              value = value.substring(0, value.indexOf('m'));
            } else if (value.contains('(')) {
              value = value.substring(0, value.indexOf('('));
            } else if (value.contains('st')) {
              final sa = javaSplit(value, 'st');
              if (sa.isNotEmpty) value = sa[0];
              final st = javaParseFloat(value);
              value = javaFormatFixed(f32(st * f32(0.907)), 1);
            } else if (value.contains('kg')) {
              final sa = javaSplit(value, 'kg');
              if (sa.isNotEmpty) value = sa[0];
              final kg = javaParseFloat(value);
              value = javaFormatFixed(f32(kg / 1000.0), 1);
            } else if (value.contains('lbs')) {
              final sa = javaSplit(value, 'lbs');
              if (sa.isNotEmpty) value = sa[0];
              final lbs = javaParseFloat(value);
              value = javaFormatFixed(f32(lbs / 2204.0), 1);
            } else if (value.contains('t')) {
              final sa = javaSplit(value, 't');
              if (sa.isNotEmpty) value = sa[0];
            }
            // found negative maxdraft values
            // no negative values
            // values are float with 2 decimals
            lookupData2[num] = i32(
              1000 + d2i(f32(javaParseFloat(value).abs() * 100.0)),
            );
          } catch (e) {
            // ignore errors
            if (showErrors) {
              stderr.writeln('error for $name  $org trans $value $e');
            }
            lookupData2[num] = 0;
          }
        }
        return newValue;
      }

      if (i == 499) {
        // System.out.println( "value limit reached for: " + name );
      }
      if (i == 500) {
        return newValue;
      }
      // unknown value, create
      final nvalues = List<BExpressionLookupValue?>.filled(
        values.length + 1,
        null,
      );
      final nhisto = Int32List(values.length + 1);
      nvalues.setRange(0, values.length, values);
      nhisto.setRange(0, histo.length, histo);
      newValue = BExpressionLookupValue(value);
      nvalues[i] = newValue;
      values = nvalues.cast<BExpressionLookupValue>();
      histo = nhisto;
      _lookupHistograms[num] = histo;
      _lookupValues[num] = values;
    }

    histo[i]++;

    // finally remember the actual data
    if (lookupData2 != null) {
      lookupData2[num] = i;
    } else {
      _lookupData[num] = i;
    }
    return newValue;
  }

  /// add a value-index to to internal array
  /// value-index means 0=unknown, 1=other, 2=value-x, ...
  ///
  /// `addLookupValue(String name, int valueIndex)`.
  void addLookupValueIndex(String name, int valueIndex) {
    final num = _lookupNumbers[name];
    if (num == null) {
      return;
    }

    // look for that value
    final nvalues = _lookupValues[num].length;
    if (valueIndex < 0 || valueIndex >= nvalues) {
      throw ArgumentError(
        'value index out of range for name $name: $valueIndex',
      );
    }
    _lookupData[num] = valueIndex;
  }

  /// special hack for yes/proposed relations:
  /// add a lookup value if not yet a smaller, &gt; 1 value was added
  /// add a 2=yes if the provided value is out of range
  /// value-index means here 0=unknown, 1=other, 2=yes, 3=proposed
  void addSmallestLookupValue(String name, int valueIndex) {
    final num = _lookupNumbers[name];
    if (num == null) {
      return;
    }

    // look for that value
    final nvalues = _lookupValues[num].length;
    final oldValueIndex = _lookupData[num];
    if (oldValueIndex > 1 && oldValueIndex < valueIndex) {
      return;
    }
    if (valueIndex >= nvalues) {
      valueIndex = nvalues - 1;
    }
    if (valueIndex < 0) {
      throw ArgumentError(
        'value index out of range for name $name: $valueIndex',
      );
    }
    _lookupData[num] = valueIndex;
  }

  bool getBooleanLookupValue(String name) {
    final num = _lookupNumbers[name];
    return num != null && _lookupData[num] == 2;
  }

  int getOutputVariableIndex(String name, bool mustExist) {
    final idx = getVariableIdx(name, false);
    if (idx < 0) {
      if (mustExist) {
        throw ArgumentError('unknown variable: $name');
      }
    } else if (idx < _minWriteIdx) {
      throw ArgumentError('bad access to global variable: $name');
    }
    final buildInVariableIdx = _buildInVariableIdx!;
    for (var i = 0; i < _nBuildInVars; i++) {
      if (buildInVariableIdx[i] == idx) {
        return i;
      }
    }
    final extended = List<int>.filled(_nBuildInVars + 1, 0);
    extended.setRange(0, _nBuildInVars, buildInVariableIdx);
    extended[_nBuildInVars] = idx;
    _buildInVariableIdx = extended;
    return _nBuildInVars++;
  }

  void setForeignContext(BExpressionContext foreignContext) {
    _foreignContext = foreignContext;
  }

  double getForeignVariableValue(int foreignIndex) {
    return _foreignContext!.getBuildInVariable(foreignIndex);
  }

  int getForeignVariableIdx(String context, String name) {
    final foreignContext = _foreignContext;
    if (foreignContext == null || context != foreignContext._context) {
      throw ArgumentError('unknown foreign context: $context');
    }
    return foreignContext.getOutputVariableIndex(name, true);
  }

  /// `parseFile(File, String)` / `parseFile(File, String, Map)`.
  void parseFile(
    File file,
    String? readOnlyContext, [
    Map<String, String>? keyValues,
  ]) {
    if (!file.existsSync()) {
      throw ArgumentError(
        'profile ${file.uri.pathSegments.last} does not exist',
      );
    }
    parseProfile(
      file.uri.pathSegments.last,
      utf8.decode(file.readAsBytesSync(), allowMalformed: true),
      readOnlyContext,
      keyValues,
    );
  }

  /// The body of `parseFile` over the profile text ([fileName] is only used
  /// in error messages), for profiles held in memory (app assets).
  void parseProfile(
    String fileName,
    String text,
    String? readOnlyContext, [
    Map<String, String>? keyValues,
  ]) {
    try {
      if (readOnlyContext != null) {
        _linenr = 1;
        final realContext = _context;
        _context = readOnlyContext;
        _expressionList = _parseText(text, keyValues);
        _variableData = Float32List(_variableNumbers.length);
        evaluateLookupData(
          _lookupData,
        ); // lookupData is dummy here - evaluate just to create the variables
        _context = realContext;
      }
      _linenr = 1;
      _minWriteIdx = _variableData == null ? 0 : _variableData!.length;
      _expressionList = _parseText(text, null);
      lastAssignedExpression = null;

      // determine the build-in variable indices
      final varNames = getBuildInVariableNames();
      _nBuildInVars = varNames.length;
      final buildInVariableIdx = List<int>.filled(_nBuildInVars, 0);
      _buildInVariableIdx = buildInVariableIdx;
      for (var vi = 0; vi < varNames.length; vi++) {
        buildInVariableIdx[vi] = getVariableIdx(varNames[vi], false);
      }

      final readOnlyData = _variableData;
      final variableData = Float32List(_variableNumbers.length);
      _variableData = variableData;
      for (var i = 0; i < _minWriteIdx; i++) {
        variableData[i] = readOnlyData![i];
      }
    } on ArgumentError catch (e) {
      throw ArgumentError(
        'ParseException $fileName at line $_linenr: ${e.message}',
      );
    }
    if (_expressionList!.isEmpty) {
      throw ArgumentError(
        '$fileName does not contain expressions for context $_context (old version?)',
      );
    }
  }

  List<BExpression> _parseText(String text, Map<String, String>? keyValues) {
    _br = text;
    _brPos = 0;
    _readerDone = false;
    final result = <BExpression>[];

    // if injected keyValues are present, create assign expressions for them
    if (keyValues != null) {
      for (final key in keyValues.keys) {
        final value = keyValues[key]!;
        result.add(
          BExpression.createAssignExpressionFromKeyValue(this, key, value),
        );
      }
    }

    for (;;) {
      final exp = BExpression.parse(this, 0);
      if (exp == null) break;
      result.add(exp);
    }
    _br = null;
    return result;
  }

  void setVariableValue(String name, double value, bool create) {
    var num = _variableNumbers[name];
    if (num != null) {
      _variableData![num] = value;
    } else if (create) {
      num = getVariableIdx(name, create);
      final readOnlyData = _variableData!;
      final minWriteIdx = readOnlyData.length;
      final variableData = Float32List(_variableNumbers.length);
      _variableData = variableData;
      for (var i = 0; i < minWriteIdx; i++) {
        variableData[i] = readOnlyData[i];
      }
      variableData[num] = value;
    }
  }

  /// `getVariableValue(String name, float defaultValue)`.
  double getVariableValue(String name, double defaultValue) {
    final num = _variableNumbers[name];
    return num == null ? defaultValue : getVariableValueByIdx(num);
  }

  /// `getVariableValue(int variableIdx)`.
  double getVariableValueByIdx(int variableIdx) {
    return _variableData![variableIdx];
  }

  int getVariableIdx(String name, bool create) {
    var num = _variableNumbers[name];
    if (num == null) {
      if (create) {
        num = _variableNumbers.length;
        _variableNumbers[name] = num;
        lastAssignedExpression!.add(null);
      } else {
        return -1;
      }
    }
    return num;
  }

  int getMinWriteIdx() {
    return _minWriteIdx;
  }

  double getLookupMatch(int nameIdx, List<int> valueIdxArray) {
    for (var i = 0; i < valueIdxArray.length; i++) {
      if (_lookupData[nameIdx] == valueIdxArray[i]) {
        return 1.0;
      }
    }
    return 0.0;
  }

  int getLookupNameIdx(String name) {
    final num = _lookupNumbers[name];
    return num ?? -1;
  }

  void markLookupIdxUsed(int idx) {
    _lookupIdxUsed![idx] = true;
  }

  bool isLookupIdxUsed(int idx) {
    final used = _lookupIdxUsed!;
    return idx < used.length && used[idx];
  }

  void setAllTagsUsed() {
    final used = _lookupIdxUsed!;
    for (var i = 0; i < used.length; i++) {
      used[i] = true;
    }
  }

  String usedTagList() {
    final sb = StringBuffer();
    final used = _lookupIdxUsed!;
    for (var inum = 0; inum < _lookupValues.length; inum++) {
      if (used[inum]) {
        if (sb.length > 0) {
          sb.write(',');
        }
        sb.write(_lookupNames[inum]);
      }
    }
    return sb.toString();
  }

  int getLookupValueIdx(int nameIdx, String value) {
    final values = _lookupValues[nameIdx];
    for (var i = 0; i < values.length; i++) {
      if (values[i].value == value) return i;
    }
    return -1;
  }

  String? parseToken() {
    for (;;) {
      final token = _parseToken();
      if (token == null) return null;
      if (token.startsWith(_contextTag)) {
        _inOurContext = token.substring(_contextTag.length) == _context;
      } else if (token.startsWith(_modelTag)) {
        _modelClass = javaTrim(token.substring(_modelTag.length));
      } else if (_inOurContext) {
        return token;
      }
    }
  }

  String? _parseToken() {
    final sb = StringBuffer();
    final sbcom = StringBuffer();
    var inComment = false;
    final br = _br!;
    for (;;) {
      final ic = _readerDone || _brPos >= br.length
          ? -1
          : br.codeUnitAt(_brPos++);
      if (ic < 0) {
        if (sb.length == 0) return null;
        _readerDone = true;
        return sb.toString();
      }
      final c = ic;
      if (c == 0x0a) _linenr++;

      if (inComment) {
        sbcom.writeCharCode(c);
        if (c == 0x0d || c == 0x0a) inComment = false;
        if (!inComment) {
          final num = _variableNumbers['check_start_way'];
          if (num != null &&
              noStartWays.isEmpty &&
              sbcom.toString().contains('noStartWay')) {
            var v = javaTrim(sbcom.toString());
            final savar = javaSplit(v, '|');
            if (savar.length == 4) {
              v = javaTrim(savar[3].substring(savar[3].indexOf('=') + 1));
              final sa = javaSplit(v, ';');
              for (final s in sa) {
                final sa2 = javaSplit(s, ',');
                final name = sa2[0];
                final value = sa2[1];
                final nidx = getLookupNameIdx(name);
                if (nidx == -1) break;
                final vidx = getLookupValueIdx(nidx, value);
                final tmp = List<int>.filled(noStartWays.length + 2, 0);
                if (noStartWays.isNotEmpty) {
                  tmp.setRange(0, noStartWays.length, noStartWays);
                }
                noStartWays = tmp;
                noStartWays[noStartWays.length - 2] = nidx;
                noStartWays[noStartWays.length - 1] = vidx;
              }
            }
          }
          sbcom.clear();
        }
        continue;
      }
      if (javaIsWhitespace(c)) {
        if (sb.length > 0) return sb.toString();
        continue;
      }
      if (c == 0x23 /* # */ && sb.length == 0) {
        inComment = true;
      } else {
        sb.writeCharCode(c);
      }
    }
  }

  double assign(int variableIdx, double value) {
    final variableData = _variableData!;
    variableData[variableIdx] = value;
    return variableData[variableIdx];
  }

  final Int32List _ld2 = Int32List(512);

  bool checkStartWay(Uint8List? ab) {
    if (ab == null) return true;
    _ld2.fillRange(0, _ld2.length, 0);
    decodeInto(_ld2, false, ab);
    for (var i = 0; i < noStartWays.length; i += 2) {
      final key = noStartWays[i];
      final value = noStartWays[i + 1];
      if (_ld2[key] == value) return false;
    }
    return true;
  }

  void freeNoWays() {
    noStartWays = <int>[];
  }
}
