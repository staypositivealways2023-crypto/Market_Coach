extension DoubleFormatting on double {
  String formatAsCurrency({String symbol = '\$', int decimals = 2}) {
    if (this >= 1e12) return '$symbol${(this / 1e12).toStringAsFixed(2)}T';
    if (this >= 1e9) return '$symbol${(this / 1e9).toStringAsFixed(2)}B';
    if (this >= 1e6) return '$symbol${(this / 1e6).toStringAsFixed(2)}M';
    return '$symbol${toStringAsFixed(decimals)}';
  }

  String formatAsPercent({int decimals = 2}) {
    final sign = this >= 0 ? '+' : '';
    return '$sign${toStringAsFixed(decimals)}%';
  }

  String formatAsPrice() {
    if (this >= 1000) return toStringAsFixed(2);
    if (this >= 1) return toStringAsFixed(2);
    return toStringAsFixed(4);
  }
}
