import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_coach/models/fundamentals.dart';
import 'package:market_coach/models/market_detail.dart';
import 'package:market_coach/models/stock_summary.dart';
import 'package:market_coach/widgets/fundamentals_card.dart';
import 'package:market_coach/widgets/realtime/price_hero_widget.dart';

void main() {
  test('FundamentalData.fromJson preserves market cap and percentage ROE', () {
    final data = FundamentalData.fromJson({
      'symbol': 'AAPL',
      'is_crypto': false,
      'current_price': 210.0,
      'market_cap': 3200000000000.0,
      'ratios': {
        'pe': 28.1,
        'ps': 7.9,
        'gross_margin': 46.9,
        'net_margin': 26.9,
        'operating_margin': 32.0,
        'roe': 151.9,
        'debt_equity': 1.63,
        'current_ratio': 0.93,
      },
      'ttm': {
        'revenue': 416160000000.0,
        'net_income': 112010000000.0,
        'eps': 7.46,
      },
      'latest_quarter': {
        'date': '2025-09-27',
        'revenue': 101000000000.0,
        'eps': 1.57,
      },
      'quarterly_eps': [],
    });

    expect(data.symbol, 'AAPL');
    expect(data.marketCap, 3200000000000.0);
    expect(data.roe, 151.9);
    expect(data.ttmRevenue, 416160000000.0);
  });

  testWidgets('PriceHeroWidget shows volume, turnover, and market cap from market range', (tester) async {
    const stock = StockSummary(
      ticker: 'AAPL',
      name: 'Apple Inc.',
      price: 210.0,
      changePercent: 1.2,
      sector: 'Technology',
      industry: 'Consumer Electronics',
    );

    const range = MarketRange(
      symbol: 'AAPL',
      currentPrice: 210.0,
      dayHigh: 212.0,
      dayLow: 207.5,
      open: 208.0,
      previousClose: 208.5,
      volume: 123456789,
      marketCap: 3200000000000.0,
      yearHigh: 250.0,
      yearLow: 150.0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: PriceHeroWidget(
              stock: stock,
              marketRange: range,
            ),
          ),
        ),
      ),
    );

    expect(find.text('VOLUME'), findsOneWidget);
    expect(find.text('TURNOVER'), findsOneWidget);
    expect(find.text('MKT CAP'), findsOneWidget);
    expect(find.text('123.46M'), findsOneWidget);
    expect(find.text('\$25.93B'), findsOneWidget);
    expect(find.text('\$3.20T'), findsOneWidget);
  });

  testWidgets('FundamentalsCard shows high ROE without rescaling it again', (tester) async {
    const data = FundamentalData(
      symbol: 'AAPL',
      isCrypto: false,
      currentPrice: 210.0,
      marketCap: 3200000000000.0,
      pe: 28.1,
      ps: 7.9,
      grossMargin: 46.9,
      netMargin: 26.9,
      operatingMargin: 32.0,
      roe: 151.9,
      debtEquity: 1.63,
      currentRatio: 0.93,
      ttmRevenue: 416160000000.0,
      ttmNetIncome: 112010000000.0,
      latestQuarterDate: '2025-09-27',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: FundamentalsCard(data: data),
          ),
        ),
      ),
    );

    expect(find.text('ROE'), findsOneWidget);
    expect(find.text('151.9%'), findsOneWidget);
    expect(find.text('Market Cap'), findsOneWidget);
    expect(find.text('\$3.20T'), findsOneWidget);
  });
}
