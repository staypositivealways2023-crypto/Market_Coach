class FundamentalData {
  final String symbol;
  final bool isCrypto;
  final double currentPrice;
  final double? marketCap;

  // Ratios (stocks only)
  final double? pe;
  final double? ps;
  final double? grossMargin;
  final double? netMargin;
  final double? operatingMargin;
  final double? roe;
  final double? debtEquity;
  final double? currentRatio;

  // TTM financials
  final double? ttmRevenue;
  final double? ttmNetIncome;
  final double? ttmEps;

  // Latest quarter
  final String? latestQuarterDate;
  final double? latestQuarterRevenue;
  final double? latestQuarterEps;

  // Quarterly history for chart
  final List<QuarterlyEps> quarterlyEps;

  const FundamentalData({
    required this.symbol,
    required this.isCrypto,
    required this.currentPrice,
    this.marketCap,
    this.pe,
    this.ps,
    this.grossMargin,
    this.netMargin,
    this.operatingMargin,
    this.roe,
    this.debtEquity,
    this.currentRatio,
    this.ttmRevenue,
    this.ttmNetIncome,
    this.ttmEps,
    this.latestQuarterDate,
    this.latestQuarterRevenue,
    this.latestQuarterEps,
    this.quarterlyEps = const [],
  });

  bool get hasRatios =>
      pe != null || grossMargin != null || netMargin != null || roe != null;

  factory FundamentalData.fromJson(Map<String, dynamic> json) {
    final ratios = json['ratios'] as Map<String, dynamic>? ?? {};
    final ttm    = json['ttm']    as Map<String, dynamic>? ?? {};
    final lq     = json['latest_quarter'] as Map<String, dynamic>? ?? {};

    final rawEps = json['quarterly_eps'] as List<dynamic>? ?? [];
    final qEps = rawEps
        .map((e) => QuarterlyEps.fromJson(e as Map<String, dynamic>))
        .toList();

    return FundamentalData(
      symbol:        json['symbol'] as String? ?? '',
      isCrypto:      json['is_crypto'] as bool? ?? false,
      currentPrice:  (json['current_price'] as num?)?.toDouble() ?? 0,
      marketCap:     (json['market_cap'] as num?)?.toDouble(),
      pe:            (ratios['pe'] as num?)?.toDouble(),
      ps:            (ratios['ps'] as num?)?.toDouble(),
      grossMargin:   (ratios['gross_margin'] as num?)?.toDouble(),
      netMargin:     (ratios['net_margin'] as num?)?.toDouble(),
      operatingMargin: (ratios['operating_margin'] as num?)?.toDouble(),
      roe:           (ratios['roe'] as num?)?.toDouble(),
      debtEquity:    (ratios['debt_equity'] as num?)?.toDouble(),
      currentRatio:  (ratios['current_ratio'] as num?)?.toDouble(),
      ttmRevenue:    (ttm['revenue'] as num?)?.toDouble(),
      ttmNetIncome:  (ttm['net_income'] as num?)?.toDouble(),
      ttmEps:        (ttm['eps'] as num?)?.toDouble(),
      latestQuarterDate:    lq['date'] as String?,
      latestQuarterRevenue: (lq['revenue'] as num?)?.toDouble(),
      latestQuarterEps:     (lq['eps'] as num?)?.toDouble(),
      quarterlyEps: qEps,
    );
  }
}

class QuarterlyEps {
  final String period;
  final String reportDate;
  final double? eps;
  final double? revenue;

  const QuarterlyEps({
    required this.period,
    required this.reportDate,
    this.eps,
    this.revenue,
  });

  factory QuarterlyEps.fromJson(Map<String, dynamic> json) {
    return QuarterlyEps(
      period:     json['period'] as String? ?? '',
      reportDate: json['report_date'] as String? ?? '',
      eps:        (json['eps'] as num?)?.toDouble(),
      revenue:    (json['revenue'] as num?)?.toDouble(),
    );
  }
}
