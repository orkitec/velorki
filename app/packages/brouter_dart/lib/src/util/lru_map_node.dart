// Port of btools.util.LruMapNode (BRouter v1.7.10).

abstract class LruMapNode {
  LruMapNode? nextInBin; // next entry for hash-bin
  LruMapNode? next; // next in lru sequence (towards mru)
  LruMapNode? previous; // previous in lru sequence (towards lru)

  int hash = 0;

  /// Java's `hashCode()`; the subclasses upstream return [hash].
  @override
  int get hashCode;

  @override
  bool operator ==(Object other);
}
