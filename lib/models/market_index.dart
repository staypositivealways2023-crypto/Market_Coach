class MarketIndex {
  final String name;
  final String ticker;
  final double value;
  final double changePercent;

  const MarketIndex({
    required this.name,
    required this.ticker,
    required this.value,
    required this.changePercent,
  });

  bool get isPositive => changePercent >= 0;
}
