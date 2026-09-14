import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/maplibre_map_controller.dart';

void main() {
  group('tolerateMapGone', () {
    test('a map whose activity was recreated is nothing to report', () async {
      await expectLater(
        tolerateMapGone(
          () async => throw PlatformException(
            code: 'MAP_NOT_READY',
            message: 'Map is not ready (activity may have been recreated)',
          ),
        ),
        completes,
      );
    });

    test('a layer the style already has is nothing to report', () async {
      await expectLater(
        tolerateMapGone(
          () async => throw PlatformException(
            code: 'error',
            message: 'Layer velorki-route-main-casing already exists',
          ),
        ),
        completes,
      );
    });

    test('a style iOS no longer has is nothing to report', () async {
      await expectLater(
        tolerateMapGone(
          () async => throw PlatformException(
            code: 'styleNotFound',
            message: 'Style not found',
          ),
        ),
        completes,
      );
    });

    test('a source iOS dropped mid-attach is nothing to report', () async {
      await expectLater(
        tolerateMapGone(
          () async => throw PlatformException(
            code: 'sourceNotFound',
            message: 'Source not found',
            details: 'Source with id velorki-position not found.',
          ),
        ),
        completes,
      );
    });

    test('a torn-down method channel is nothing to report', () async {
      await expectLater(
        tolerateMapGone(
          () async => throw MissingPluginException(
            'No implementation found for method circleLayer#add',
          ),
        ),
        completes,
      );
    });

    test('any other platform error still surfaces', () async {
      await expectLater(
        tolerateMapGone(
          () async =>
              throw PlatformException(code: 'error', message: 'style broken'),
        ),
        throwsA(isA<PlatformException>()),
      );
    });

    test('a call that works is passed through', () async {
      var ran = false;
      await tolerateMapGone(() async => ran = true);
      expect(ran, isTrue);
    });
  });
}
