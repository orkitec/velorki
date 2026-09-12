// Port of btools.codec.TagValueWrapper (BRouter v1.7.10).

import 'dart:typed_data';

/// TagValueWrapper wrapps a description bitmap
/// to add the access-type
class TagValueWrapper {
  Uint8List? data;
  int accessType = 0;
}
