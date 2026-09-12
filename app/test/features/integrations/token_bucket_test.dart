import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/common/data/token_bucket.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';

void main() {
  var now = DateTime.utc(2026, 9, 12, 12);

  setUp(() => now = DateTime.utc(2026, 9, 12, 12));

  TokenBucket bucket({int capacity = 3}) => TokenBucket(
    capacity: capacity,
    window: const Duration(minutes: 15),
    clock: () => now,
  );

  test('allows exactly the capacity inside one window', () {
    final b = bucket();
    expect(b.available, 3);
    expect(b.tryConsume(), isTrue);
    expect(b.tryConsume(), isTrue);
    expect(b.tryConsume(), isTrue);
    expect(b.tryConsume(), isFalse);
    expect(b.available, 0);
  });

  test('the window slides rather than resetting', () {
    final b = bucket();
    b
      ..tryConsume()
      ..tryConsume()
      ..tryConsume();
    expect(b.tryConsume(), isFalse);

    // 14 minutes on: the first call is still inside the window.
    now = now.add(const Duration(minutes: 14));
    expect(b.tryConsume(), isFalse);
    expect(b.retryAfter, const Duration(minutes: 1));

    // A minute later the oldest call falls out and one slot is free again.
    now = now.add(const Duration(minutes: 1));
    expect(b.available, 3);
    expect(b.tryConsume(), isTrue);
  });

  test('an empty bucket throws a friendly, rate-limited exception', () {
    final b = bucket(capacity: 1)..consume();

    expect(
      b.consume,
      throwsA(
        isA<IntegrationException>()
            .having((e) => e.failure, 'failure', IntegrationFailure.rateLimited)
            .having((e) => e.message, 'message', contains('Strava'))
            .having((e) => e.retryAfter, 'retryAfter', isNotNull),
      ),
    );
  });

  test('the Strava bucket is 90 reads per 15 minutes', () {
    final b = TokenBucket.stravaReads(clock: () => now);
    expect(b.capacity, 90);
    expect(b.window, const Duration(minutes: 15));
    for (var i = 0; i < 90; i++) {
      expect(b.tryConsume(), isTrue, reason: 'call ${i + 1}');
    }
    expect(b.tryConsume(), isFalse);
  });

  test('reset empties the bucket, which is what a disconnect does', () {
    final b = bucket(capacity: 1)..consume();
    expect(b.tryConsume(), isFalse);
    b.reset();
    expect(b.tryConsume(), isTrue);
  });
}
