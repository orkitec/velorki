// Port of btools.router.VoiceHintList (BRouter v1.7.10).
//
// Container for a voice hint
// (both input- and result data for voice hint processing)

import 'voice_hint.dart';

class VoiceHintList {
  static const int transModeNone = 0;
  static const int transModeFoot = 1;
  static const int transModeBike = 2;
  static const int transModeCar = 3;

  int _transportMode = transModeBike;
  int turnInstructionMode = 0;
  List<VoiceHint> list = <VoiceHint>[];

  void setTransportMode(bool isCar, bool isBike) {
    _transportMode = isCar
        ? transModeCar
        : (isBike ? transModeBike : transModeFoot);
  }

  /// `setTransportMode(int mode)`
  void setTransportModeValue(int mode) {
    _transportMode = mode;
  }

  String getTransportMode() {
    String ret;
    switch (_transportMode) {
      case transModeFoot:
        ret = 'foot';
        break;
      case transModeCar:
        ret = 'car';
        break;
      case transModeBike:
      default:
        ret = 'bike';
        break;
    }
    return ret;
  }

  int transportMode() {
    return _transportMode;
  }

  int getLocusRouteType() {
    if (_transportMode == transModeCar) {
      return 0;
    }
    if (_transportMode == transModeBike) {
      return 5;
    }
    return 3; // foot
  }
}
