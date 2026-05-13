/// Probabilistic Engine result — Phase 4.
///
/// Mirrors the GET /api/probabilistic/{symbol} response from
/// python-backend/app/routers/analysis.py.

class MonteCarloData {
  final double currentPrice;
  final double expectedPrice;
  final Map<String, double> percentiles; // keys: "10","25","50","75","90"
  final double probProfit;
  final double? var95;       // % loss at 95th confidence (positive number)
  final double? cvar95;      // expected % loss beyond VaR (positive number)
  final bool blackSwanProne;
  final double? excessKurtosis;
  final double annualisedVol;

  const MonteCarloData({
    required this.currentPrice,
    required this.expectedPrice,
    required this.percentiles,
    required this.probProfit,
    this.var95,
    this.cvar95,
    required this.blackSwanProne,
    this.excessKurtosis,
    required this.annualisedVol,
  });

  factory MonteCarloData.fromJson(Map<String, dynamic> json) {
    final pct = (json['percentiles'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(k, (v as num).toDouble()),
    );
    return MonteCarloData(
      currentPrice:    (json['current_price'] as num).toDouble(),
      expectedPrice:   (json['expected_price'] as num).toDouble(),
      percentiles:     pct,
      probProfit:      (json['prob_profit'] as num).toDouble(),
      var95:           (json['var_95'] as num?)?.toDouble(),
      cvar95:          (json['cvar_95'] as num?)?.toDouble(),
      blackSwanProne:  json['black_swan_prone'] as bool? ?? false,
      excessKurtosis:  (json['excess_kurtosis'] as num?)?.toDouble(),
      annualisedVol:   (json['annualised_vol'] as num).toDouble(),
    );
  }

  double? get p10 => percentiles['10'];
  double? get p25 => percentiles['25'];
  double? get p50 => percentiles['50'];
  double? get p75 => percentiles['75'];
  double? get p90 => percentiles['90'];
}

class BayesianData {
  final double posteriorMean;
  final List<double> credibleInterval90; // [low, high]
  final double? priorWeightPct;
  final double? dataImpliedTarget;

  const BayesianData({
    required this.posteriorMean,
    required this.credibleInterval90,
    this.priorWeightPct,
    this.dataImpliedTarget,
  });

  factory BayesianData.fromJson(Map<String, dynamic> json) {
    final ci = (json['credible_interval_90'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [0.0, 0.0];
    return BayesianData(
      posteriorMean:       (json['posterior_mean'] as num).toDouble(),
      credibleInterval90:  ci,
      priorWeightPct:      (json['prior_weight_pct'] as num?)?.toDouble(),
      dataImpliedTarget:   (json['data_implied_target'] as num?)?.toDouble(),
    );
  }
}

class RedditSentimentData {
  final double sentimentScore;  // weighted VADER [-1, 1]
  final int mentionCount;
  final String sentimentLabel;  // bullish | bearish | neutral
  final List<Map<String, dynamic>> topPosts;

  const RedditSentimentData({
    required this.sentimentScore,
    required this.mentionCount,
    required this.sentimentLabel,
    required this.topPosts,
  });

  factory RedditSentimentData.fromJson(Map<String, dynamic> json) {
    return RedditSentimentData(
      sentimentScore: (json['sentiment_score'] as num?)?.toDouble() ?? 0.0,
      mentionCount:   json['mention_count'] as int? ?? 0,
      sentimentLabel: json['sentiment_label'] as String? ?? 'neutral',
      topPosts: (json['top_posts'] as List<dynamic>?)
              ?.map((p) => Map<String, dynamic>.from(p as Map))
              .toList() ??
          [],
    );
  }
}

class ProbabilisticData {
  final String symbol;
  final double currentPrice;
  final int horizonDays;
  final String generatedAt;
  final MonteCarloData monteCarlo;
  final BayesianData bayesian;
  final int overallConviction;      // 0–100
  final String summary;
  final RedditSentimentData? reddit;

  // Macro (flattened from response)
  final String? macroRegime;
  final int? macroRiskScore;

  const ProbabilisticData({
    required this.symbol,
    required this.currentPrice,
    required this.horizonDays,
    required this.generatedAt,
    required this.monteCarlo,
    required this.bayesian,
    required this.overallConviction,
    required this.summary,
    this.reddit,
    this.macroRegime,
    this.macroRiskScore,
  });

  factory ProbabilisticData.fromJson(Map<String, dynamic> json) {
    final mc   = MonteCarloData.fromJson(json['monte_carlo'] as Map<String, dynamic>);
    final bayes = BayesianData.fromJson(json['bayesian'] as Map<String, dynamic>);

    final macroJson = json['macro'] as Map<String, dynamic>?;
    final redditJson = json['reddit'] as Map<String, dynamic>?;

    return ProbabilisticData(
      symbol:           json['symbol'] as String,
      currentPrice:     (json['current_price'] as num).toDouble(),
      horizonDays:      json['horizon_days'] as int? ?? 21,
      generatedAt:      json['generated_at'] as String? ?? '',
      monteCarlo:       mc,
      bayesian:         bayes,
      overallConviction: json['overall_conviction'] as int? ?? 50,
      summary:          json['summary'] as String? ?? '',
      reddit: redditJson != null ? RedditSentimentData.fromJson(redditJson) : null,
      macroRegime:      macroJson?['regime'] as String?,
      macroRiskScore:   macroJson?['risk_score'] as int?,
    );
  }
}
