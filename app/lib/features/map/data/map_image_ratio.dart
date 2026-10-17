// How a bitmap the app paints at the screen's density becomes a style image
// of the right size: on the phone the plugin takes it at the device's scale;
// in the browser it registers every image at one pixel per point, so the
// ratio is put in on the way.
export 'map_image_ratio_native.dart'
    if (dart.library.js_interop) 'map_image_ratio_web.dart';
