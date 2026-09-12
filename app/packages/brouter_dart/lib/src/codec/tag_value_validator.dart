// Port of btools.codec.TagValueValidator (BRouter v1.7.10).

import 'dart:typed_data';

abstract class TagValueValidator {
  /// Returns 0 = nothing, 1=no matching, 2=normal for the way description
  int accessType(Uint8List tagValueSet);

  Uint8List unify(Uint8List tagValueSet, int offset, int len);

  bool isLookupIdxUsed(int idx);

  void setDecodeForbidden(bool decodeForbidden);

  bool checkStartWay(Uint8List ab);
}
