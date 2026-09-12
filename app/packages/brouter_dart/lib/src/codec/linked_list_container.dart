// Port of btools.codec.LinkedListContainer (BRouter v1.7.10).

import 'dart:typed_data';

/// Simple container for a list of lists of integers
class LinkedListContainer {
  /// Construct a container for the given number of lists
  ///
  /// If no default-buffer is given, an int[nlists*4] is constructed,
  /// able to hold 2 entries per list on average
  LinkedListContainer(int nlists, Int32List? defaultbuffer)
    : _ia = defaultbuffer ?? Int32List(nlists * 4),
      _startpointer = Int32List(nlists);

  Int32List _ia; // prev, data, prev, data, ...
  int _size = 0;
  final Int32List _startpointer; // 0=void, odd=head-data-cell
  int _listpointer = 0;

  /// Add a data element to the given list
  void addDataElement(int listNr, int data) {
    if (_size + 2 > _ia.length) {
      _resize();
    }
    _ia[_size++] = _startpointer[listNr];
    _startpointer[listNr] = _size;
    _ia[_size++] = data;
  }

  /// Initialize a list for reading
  ///
  /// Returns the number of entries in that list
  int initList(int listNr) {
    var cnt = 0;
    var lp = _listpointer = _startpointer[listNr];
    while (lp != 0) {
      lp = _ia[lp - 1];
      cnt++;
    }
    return cnt;
  }

  /// Get a data element from the list previously initialized.
  /// Data elements are return in reverse order (lifo)
  int getDataElement() {
    if (_listpointer == 0) {
      throw ArgumentError('no more element!');
    }
    final data = _ia[_listpointer];
    _listpointer = _ia[_listpointer - 1];
    return data;
  }

  void _resize() {
    final ia2 = Int32List(2 * _ia.length);
    ia2.setRange(0, _ia.length, _ia);
    _ia = ia2;
  }
}
