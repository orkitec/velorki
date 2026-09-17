/// A download size for a rider, not for a machine.
///
/// The units are the SI symbols, which are written the same way in every
/// language, so the figure needs no translation — only the decimal separator
/// would differ, and one digit of a megabyte is not worth an ARB entry.
library;

/// "12.3 MB", or "—" while the size is still unknown.
String formatBytes(int bytes) {
  if (bytes <= 0) return '—';
  const units = <String>['B', 'kB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}
