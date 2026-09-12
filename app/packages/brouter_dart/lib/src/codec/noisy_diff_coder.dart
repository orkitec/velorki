// Port of btools.codec.NoisyDiffCoder (BRouter v1.7.10).

import 'dart:typed_data';

import '../jvm.dart';
import 'stat_coder_context.dart';

/// Encoder/Decoder for signed integers that automatically detects the typical
/// range of these numbers to determine a noisy-bit count as a very simple
/// dictionary
///
/// Adapted for 3-pass encoding (counters -> statistics -> encoding )
/// but doesn't do anything at pass1
class NoisyDiffCoder {
  /// Create a decoder and read the noisy-bit count from the gibe context
  NoisyDiffCoder.decoder(StatCoderContext bc) {
    _noisybits = bc.decodeVarBits();
    _bc = bc;
  }

  /// Create an encoder for 3-pass-encoding
  NoisyDiffCoder();

  int _tot = 0;
  Int32List? _freqs;
  int _noisybits = 0;
  StatCoderContext? _bc;
  int _pass = 0;

  /// encodes a signed int (pass3 only, stats collection in pass2)
  void encodeSignedValue(int value) {
    if (_pass == 3) {
      _bc!.encodeNoisyDiff(value, _noisybits);
    } else if (_pass == 2) {
      _count(value < 0 ? i32(-value) : value);
    }
  }

  /// decodes a signed int
  int decodeSignedValue() {
    return _bc!.decodeNoisyDiff(_noisybits);
  }

  /// Starts a new encoding pass and (in pass3) calculates the noisy-bit count
  /// from the stats collected in pass2 and writes that to the given context
  void encodeDictionary(StatCoderContext bc) {
    if (++_pass == 3) {
      // how many noisy bits?
      for (_noisybits = 0; _noisybits < 14 && _tot > 0; _noisybits++) {
        if (_freqs![_noisybits] < (_tot >> 1)) break;
      }
      bc.encodeVarBits(_noisybits);
    }
    _bc = bc;
  }

  void _count(int value) {
    final freqs = _freqs ??= Int32List(14);
    var bm = 1;
    for (var i = 0; i < 14; i++) {
      if (value < bm) {
        break;
      } else {
        freqs[i]++;
      }
      bm <<= 1;
    }
    _tot++;
  }
}
