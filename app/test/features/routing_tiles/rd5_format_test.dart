import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/routing_tiles/domain/rd5_format.dart';

void main() {
  test('parses the manifest form and the lookups.dat header', () {
    expect(Rd5Format.parse('11.2'), const Rd5Format(11, 2));
    expect(Rd5Format.parse(' 12.0 '), const Rd5Format(12, 0));
    expect(Rd5Format.parse('11'), isNull);
    expect(Rd5Format.parse('eleven.two'), isNull);
    expect(Rd5Format.parse(null), isNull);
    expect(
      Rd5Format.fromLookups('---lookupversion:11\n---minorversion:2\n\n'),
      const Rd5Format(11, 2),
    );
    expect(Rd5Format.fromLookups('---context:way\nhighway;...'), isNull);
  });

  test('reads its own and older minor versions, nothing newer', () {
    const app = Rd5Format(11, 2);

    expect(app.canRead(const Rd5Format(11, 2)), isTrue);
    expect(app.canRead(const Rd5Format(11, 0)), isTrue);
    expect(app.canRead(const Rd5Format(11, 3)), isFalse);
    expect(app.canRead(const Rd5Format(12, 0)), isFalse);
    expect(app.canRead(const Rd5Format(10, 9)), isFalse);
  });

  test('an unknown version is let through for the engine to judge', () {
    const app = Rd5Format(11, 2);

    expect(app.canReadVersion(null), isTrue);
    expect(app.canReadVersion(''), isTrue);
    expect(app.canReadVersion('garbage'), isTrue);
    expect(app.canReadVersion('11.3'), isFalse);
    expect(app.canReadVersion('11.1'), isTrue);
  });
}
