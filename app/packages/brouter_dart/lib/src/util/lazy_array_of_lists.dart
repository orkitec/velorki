// Port of btools.util.LazyArrayOfLists (BRouter v1.7.10).

/// Behaves like an Array of list
/// with lazy list-allocation at getList
class LazyArrayOfLists<E> {
  LazyArrayOfLists(int size) : _lists = List<List<E>?>.filled(size, null);

  final List<List<E>?> _lists;

  List<E> getList(int idx) {
    var list = _lists[idx];
    if (list == null) {
      list = <E>[];
      _lists[idx] = list;
    }
    return list;
  }

  int getSize(int idx) {
    final list = _lists[idx];
    return list == null ? 0 : list.length;
  }

  /// `ArrayList.trimToSize()` has no Dart equivalent; a no-op.
  void trimAll() {}
}
