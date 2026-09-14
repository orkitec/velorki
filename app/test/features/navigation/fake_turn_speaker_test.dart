import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/testing/fake_turn_speaker.dart';

void main() {
  test('the fake speaker writes down what it was asked to say', () async {
    final speaker = FakeTurnSpeaker();

    await speaker.speak('Now turn left');
    await speaker.speak('You have arrived');
    await speaker.stop();
    await speaker.dispose();

    expect(speaker.spoken, ['Now turn left', 'You have arrived']);
    expect(speaker.stops, 1);
    expect(speaker.disposed, isTrue);
  });
}
