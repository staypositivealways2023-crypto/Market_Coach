class Quote {
  final String symbol;
  final double price;
  final double changePercent;

  const Quote({
    required this.symbol,
    required this.price,
    required this.changePercent,
  });

  bool get isPositive => changePercent >= 0;
}
