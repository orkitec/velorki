// Port of btools.util.ReducedMedianFilter (BRouter v1.7.10).

import 'dart:typed_data';

/// a median filter with additional edge reduction
class ReducedMedianFilter {
  ReducedMedianFilter(int size)
    : _weights = Float64List(size),
      _values = Int32List(size);

  int _nsamples = 0;
  final Float64List _weights;
  final Int32List _values;

  void reset() {
    _nsamples = 0;
  }

  void addSample(double weight, int value) {
    if (weight > 0.0) {
      for (var i = 0; i < _nsamples; i++) {
        if (_values[i] == value) {
          _weights[i] += weight;
          return;
        }
      }
      _weights[_nsamples] = weight;
      _values[_nsamples] = value;
      _nsamples++;
    }
  }

  double calcEdgeReducedMedian(double fraction) {
    _removeEdgeWeight((1.0 - fraction) / 2.0, true);
    _removeEdgeWeight((1.0 - fraction) / 2.0, false);

    var totalWeight = 0.0;
    var totalValue = 0.0;
    for (var i = 0; i < _nsamples; i++) {
      final w = _weights[i];
      totalWeight += w;
      totalValue += w * _values[i];
    }
    return totalValue / totalWeight;
  }

  void _removeEdgeWeight(double excessWeight, bool high) {
    while (excessWeight > 0.0) {
      // first pass to find minmax value
      var totalWeight = 0.0;
      var minmax = 0;
      for (var i = 0; i < _nsamples; i++) {
        final w = _weights[i];
        if (w > 0.0) {
          final v = _values[i];
          if (totalWeight == 0.0 || (high ? v > minmax : v < minmax)) {
            minmax = v;
          }
          totalWeight += w;
        }
      }

      if (totalWeight < excessWeight) {
        throw ArgumentError('ups, not enough weight to remove');
      }

      // second pass to remove
      for (var i = 0; i < _nsamples; i++) {
        if (_values[i] == minmax && _weights[i] > 0.0) {
          if (excessWeight > _weights[i]) {
            excessWeight -= _weights[i];
            _weights[i] = 0.0;
          } else {
            _weights[i] -= excessWeight;
            excessWeight = 0.0;
          }
        }
      }
    }
  }
}
