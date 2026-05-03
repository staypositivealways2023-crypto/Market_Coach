/// Models for Phase 5 real-time market data endpoints.
///
/// Endpoint → Model:
///   GET /api/market/moneyflow/{symbol}      → MoneyFlowData
///   GET /api/market/marketposition/{symbol} → MarketPositionData
///   GET /api/market/options/{symbol}        → OptionsData
///   WS  /api/market/stream/{symbol}         → PriceTick

// ── Money Flow ────────────────────────────────────────────────────────────────

class MoneyFlowData {
  /// Chaikin Money Flow (20-period). Range: -1 to +1.
  /// > +0.05 = accumulation; < -0.05 = distribution.
  final double cmf20;

  /// Human-readable signal: 'accumulation' | 'distribution' | 'neutral'
  final String cmfSignal;

  /// Net dollar flow over the look-back window (positive = net buying).
  final double? netFlowUsd;

  /// Smoothed 20-day MFV proxy for institutional flow.
  final double? institutionalFlow;

  /// Short 3-day MFV proxy for retail flow.
  final double? retailFlow;

  /// True when institutional and retail flow diverge significantly.
  final bool? flowDivergence;

  /// 'increasing' | 'decreasing' | 'stable'
  final String? volumeTrend;

  final String source;

  const MoneyFlowData({
    required this.cmf20,
    required this.cmfSignal,
    this.netFlowUsd,
    this.institutionalFlow,
    this.retailFlow,
    this.flowDivergence,
    this.volumeTrend,
    required this.source,
  });

  factory MoneyFlowData.fromMap(Map<String, dynamic> m) => MoneyFlowData(
        cmf20: (m['cmf_20'] as num? ?? 0).toDouble(),
        cmfSignal: m['cmf_signal'] as String? ?? 'neutral',
        netFlowUsd: m['net_flow_usd'] != null
            ? (m['net_flow_usd'] as num).toDouble()
            : null,
        institutionalFlow: m['institutional_flow'] != null
            ? (m['institutional_flow'] as num).toDouble()
            : null,
        retailFlow: m['retail_flow'] != null
            ? (m['retail_flow'] as num).toDouble()
            : null,
        flowDivergence: m['flow_divergence'] as bool?,
        volumeTrend: m['volume_trend'] as String?,
        source: m['source'] as String? ?? 'unknown',
      );
}

// ── Market Position ───────────────────────────────────────────────────────────

class MarketPositionData {
  /// Net positioning score: -1.0 (max short) to +1.0 (max long).
  final double netPositionScore;

  /// 'strongly_long' | 'long' | 'neutral' | 'short' | 'strongly_short'
  final String positionLabel;

  /// ADX strength measure. > 25 = trending; < 20 = ranging.
  final double? adxStrength;

  /// 'bullish' | 'bearish' | 'neutral'
  final String? trendDirection;

  /// Smart money signal derived from large-block flow analysis.
  final String? smartMoneySignal;

  /// Key institutional reference price (VWAP).
  final double? keyPriceLevel;

  final String source;

  const MarketPositionData({
    required this.netPositionScore,
    required this.positionLabel,
    this.adxStrength,
    this.trendDirection,
    this.smartMoneySignal,
    this.keyPriceLevel,
    required this.source,
  });

  factory MarketPositionData.fromMap(Map<String, dynamic> m) =>
      MarketPositionData(
        netPositionScore:
            (m['net_position_score'] as num? ?? 0).toDouble(),
        positionLabel:
            m['position_label'] as String? ?? 'neutral',
        adxStrength: m['adx_strength'] != null
            ? (m['adx_strength'] as num).toDouble()
            : null,
        trendDirection: m['trend_direction'] as String?,
        smartMoneySignal: m['smart_money_signal'] as String?,
        keyPriceLevel: m['key_price_level'] != null
            ? (m['key_price_level'] as num).toDouble()
            : null,
        source: m['source'] as String? ?? 'unknown',
      );
}

// ── Options ───────────────────────────────────────────────────────────────────

class OptionsStrike {
  final double strike;
  final int callOi;
  final int putOi;
  final int callVolume;
  final int putVolume;
  final double? callIv;
  final double? putIv;

  const OptionsStrike({
    required this.strike,
    required this.callOi,
    required this.putOi,
    required this.callVolume,
    required this.putVolume,
    this.callIv,
    this.putIv,
  });

  factory OptionsStrike.fromMap(Map<String, dynamic> m) => OptionsStrike(
        strike: (m['strike'] as num).toDouble(),
        callOi: (m['call_oi'] as num? ?? 0).toInt(),
        putOi: (m['put_oi'] as num? ?? 0).toInt(),
        callVolume: (m['call_volume'] as num? ?? 0).toInt(),
        putVolume: (m['put_volume'] as num? ?? 0).toInt(),
        callIv: m['call_iv'] != null ? (m['call_iv'] as num).toDouble() : null,
        putIv: m['put_iv'] != null ? (m['put_iv'] as num).toDouble() : null,
      );
}

class OptionsData {
  /// Whether options data is available for this symbol.
  final bool available;

  final String? note;
  final String? expiry;
  final double? currentPrice;

  /// At-the-money implied volatility (annualised, e.g. 0.35 = 35%).
  final double? atmIv;

  /// Put IV minus Call IV at the same strike — positive = put skew (fear).
  final double? ivSkew;

  /// Put/Call ratio by volume.
  final double? pcrVolume;

  /// Put/Call ratio by open interest.
  final double? pcrOi;

  /// 'bearish' | 'neutral' | 'bullish'
  final String? pcrSignal;

  /// Price at which option writers face maximum loss (pin risk).
  final double? maxPain;

  /// Distance of maxPain from currentPrice as percentage.
  final double? maxPainDistancePct;

  final List<OptionsStrike> topCallStrikes;
  final List<OptionsStrike> topPutStrikes;

  final int? totalCallOi;
  final int? totalPutOi;

  final String source;

  const OptionsData({
    required this.available,
    this.note,
    this.expiry,
    this.currentPrice,
    this.atmIv,
    this.ivSkew,
    this.pcrVolume,
    this.pcrOi,
    this.pcrSignal,
    this.maxPain,
    this.maxPainDistancePct,
    this.topCallStrikes = const [],
    this.topPutStrikes = const [],
    this.totalCallOi,
    this.totalPutOi,
    required this.source,
  });

  factory OptionsData.fromMap(Map<String, dynamic> m) => OptionsData(
        available: m['available'] as bool? ?? false,
        note: m['note'] as String?,
        expiry: m['expiry'] as String?,
        currentPrice: m['current_price'] != null
            ? (m['current_price'] as num).toDouble()
            : null,
        atmIv:
            m['atm_iv'] != null ? (m['atm_iv'] as num).toDouble() : null,
        ivSkew:
            m['iv_skew'] != null ? (m['iv_skew'] as num).toDouble() : null,
        pcrVolume: m['pcr_volume'] != null
            ? (m['pcr_volume'] as num).toDouble()
            : null,
        pcrOi:
            m['pcr_oi'] != null ? (m['pcr_oi'] as num).toDouble() : null,
        pcrSignal: m['pcr_signal'] as String?,
        maxPain:
            m['max_pain'] != null ? (m['max_pain'] as num).toDouble() : null,
        maxPainDistancePct: m['max_pain_distance_pct'] != null
            ? (m['max_pain_distance_pct'] as num).toDouble()
            : null,
        topCallStrikes: (m['top_call_strikes'] as List<dynamic>? ?? [])
            .map((e) => OptionsStrike.fromMap(e as Map<String, dynamic>))
            .toList(),
        topPutStrikes: (m['top_put_strikes'] as List<dynamic>? ?? [])
            .map((e) => OptionsStrike.fromMap(e as Map<String, dynamic>))
            .toList(),
        totalCallOi: m['total_call_oi'] != null
            ? (m['total_call_oi'] as num).toInt()
            : null,
        totalPutOi: m['total_put_oi'] != null
            ? (m['total_put_oi'] as num).toInt()
            : null,
        source: m['source'] as String? ?? 'unknown',
      );
}

// ── Price Tick (WebSocket stream) ─────────────────────────────────────────────

class PriceTick {
  final String symbol;
  final double price;

  /// % change from open (e.g. 1.23 = +1.23%).
  final double changePct;
  final double? volume;
  final double? high;
  final double? low;
  final DateTime timestamp;

  /// 'binance' | 'yfinance_poll'
  final String source;

  const PriceTick({
    required this.symbol,
    required this.price,
    required this.changePct,
    this.volume,
    this.high,
    this.low,
    required this.timestamp,
    required this.source,
  });

  factory PriceTick.fromMap(Map<String, dynamic> m) => PriceTick(
        symbol: m['symbol'] as String? ?? '',
        price: (m['price'] as num? ?? 0).toDouble(),
        changePct: (m['change'] as num? ?? 0).toDouble(),
        volume:
            m['volume'] != null ? (m['volume'] as num).toDouble() : null,
        high: m['high'] != null ? (m['high'] as num).toDouble() : null,
        low: m['low'] != null ? (m['low'] as num).toDouble() : null,
        timestamp: m['timestamp'] != null
            ? DateTime.tryParse(m['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
        source: m['source'] as String? ?? 'unknown',
      );
}
