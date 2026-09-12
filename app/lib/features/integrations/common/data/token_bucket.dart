import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/integration_exception.dart';

/// A sliding-window rate limiter, kept on the client so the app stops itself
/// before a service does.
///
/// Strava's read limit is 100 requests per 15 minutes per athlete; the app
/// budgets 90 so the remaining ten are left for whatever the rider does in
/// another app that shares the same application quota. The window slides
/// rather than resetting on a quarter hour, which is the pessimistic reading
/// of the limit and therefore the safe one.
///
/// This is deliberately not persisted: a restart clears it, and Strava's own
/// 429 is the backstop. Persisting it would punish a rider who reinstalled.
class TokenBucket {
  /// Creates a bucket that allows [capacity] calls per [window].
  TokenBucket({
    required this.capacity,
    required this.window,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Strava's read bucket: 90 calls per 15 minutes.
  factory TokenBucket.stravaReads({DateTime Function()? clock}) => TokenBucket(
    capacity: stravaReadCapacity,
    window: stravaReadWindow,
    clock: clock,
  );

  /// How many Strava reads the app allows itself per [stravaReadWindow].
  static const int stravaReadCapacity = 90;

  /// The window Strava counts reads over.
  static const Duration stravaReadWindow = Duration(minutes: 15);

  /// How many calls fit in one [window].
  final int capacity;

  /// The length of the sliding window.
  final Duration window;

  final DateTime Function() _clock;
  final Queue<DateTime> _taken = Queue<DateTime>();

  /// How many calls are still allowed right now.
  int get available {
    _prune();
    return capacity - _taken.length;
  }

  /// How long until the next call is allowed; zero when one is allowed now.
  Duration get retryAfter {
    _prune();
    if (_taken.length < capacity) return Duration.zero;
    final free = _taken.first.add(window);
    final wait = free.difference(_clock());
    return wait.isNegative ? Duration.zero : wait;
  }

  /// Takes one slot, or returns `false` when the bucket is empty.
  bool tryConsume() {
    _prune();
    if (_taken.length >= capacity) return false;
    _taken.addLast(_clock());
    return true;
  }

  /// Takes one slot or throws a [IntegrationException] the UI can show.
  void consume({String what = 'Strava'}) {
    if (tryConsume()) return;
    final wait = retryAfter;
    throw IntegrationException(
      IntegrationFailure.rateLimited,
      'Too many $what requests. $what allows $capacity reads every '
      '${window.inMinutes} minutes — try again in '
      '${_minutes(wait)}.',
      retryAfter: wait,
    );
  }

  /// Empties the bucket, which is what a disconnect amounts to.
  void reset() => _taken.clear();

  void _prune() {
    final cutoff = _clock().subtract(window);
    while (_taken.isNotEmpty && !_taken.first.isAfter(cutoff)) {
      _taken.removeFirst();
    }
  }

  static String _minutes(Duration wait) {
    final minutes = wait.inSeconds <= 60 ? 1 : (wait.inSeconds / 60).ceil();
    return minutes == 1 ? 'a minute' : '$minutes minutes';
  }
}

/// The app-wide Strava read bucket. Kept alive so it survives screen changes.
final stravaReadBucketProvider = Provider<TokenBucket>(
  (ref) => TokenBucket.stravaReads(),
);
