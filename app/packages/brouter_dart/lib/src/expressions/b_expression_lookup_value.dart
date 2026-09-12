// Port of btools.expressions.BExpressionLookupValue (BRouter v1.7.10).

/// A lookup value with optional aliases
///
/// toString just gives the primary value,
/// equals just compares against primary value
/// matches() also compares aliases
class BExpressionLookupValue {
  BExpressionLookupValue(this.value);

  String value;
  List<String>? aliases;

  @override
  String toString() => value;

  void addAlias(String alias) {
    (aliases ??= <String>[]).add(alias);
  }

  /// Upstream's `equals(Object)` accepts a `String` or another lookup value
  /// and compares the primary value only. It is the `==` of this class
  /// (`values[i].equals("*")` and `values[i].equals(value)` in the context).
  @override
  bool operator ==(Object o) {
    if (o is String) return value == o;
    if (o is BExpressionLookupValue) return value == o.value;
    return false;
  }

  @override
  int get hashCode => value.hashCode;

  bool matches(String s) {
    if (value == s) return true;
    final a = aliases;
    if (a != null) {
      for (final alias in a) {
        if (alias == s) return true;
      }
    }
    return false;
  }
}
