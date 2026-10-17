import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/platform_view_hit_test.dart';

class _FakeController extends PlatformViewController {
  @override
  int get viewId => 1;

  @override
  Future<void> clearFocus() async {}

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('the map takes a pointer only where nothing is over it', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            PlatformViewSurface(
              controller: _FakeController(),
              gestureRecognizers:
                  const <Factory<OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            ),
            // A card over the map, with a button on it and an empty corner.
            Positioned(
              left: 0,
              top: 400,
              width: 300,
              height: 200,
              child: ColoredBox(
                color: const Color(0xff000000),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: GestureDetector(
                    onTap: () {},
                    child: const SizedBox(width: 80, height: 40),
                  ),
                ),
              ),
            ),
            // Glass that draws but takes no pointer.
            const Positioned(
              left: 400,
              top: 0,
              width: 100,
              height: 100,
              child: IgnorePointer(child: ColoredBox(color: Color(0x80ffffff))),
            ),
          ],
        ),
      ),
    );
    final viewId = tester.view.viewId;

    expect(platformViewAt(const Offset(600, 200), viewId), isTrue);
    expect(platformViewAt(const Offset(450, 50), viewId), isTrue);
    // A browser's pointer between pixels, on the button and on the card.
    expect(platformViewAt(const Offset(20.66, 410.33), viewId), isFalse);
    expect(platformViewAt(const Offset(250.5, 580.25), viewId), isFalse);
    expect(platformViewAt(const Offset(300.5, 580.25), viewId), isTrue);
  });
}
