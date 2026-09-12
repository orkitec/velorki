// Port of btools.util.IByteArrayUnifier (BRouter v1.7.10).

import 'dart:typed_data';

abstract class IByteArrayUnifier {
  Uint8List unify(Uint8List ab, int offset, int len);
}
