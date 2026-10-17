/// Runs [add], which registers the style image [name] painted at
/// [pixelRatio] pixels per logical pixel. The phone's plugin already takes
/// a bitmap at the device's scale, and replaces an image of the same name.
Future<void> addImageAtRatio(
  String name,
  double pixelRatio,
  Future<void> Function() add,
) => add();
