import 'package:flutter/material.dart';

import '../market/market_screen.dart';
import '../paper_trading/paper_trading_screen.dart';

/// Trade tab — wraps Market (stocks/crypto) and Paper Trading in a TabBar.
class TradeScreen extends StatelessWidget {
  const TradeScreen({super.key});

  static const _tabs = [
    Tab(text: 'Markets'),
    Tab(text: 'Paper Trade'),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'Trade',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          bottom: TabBar(
            tabs: _tabs,
            indicatorColor: Theme.of(context).colorScheme.primary,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        body: const TabBarView(
          children: [
            MarketScreen(),
            PaperTradingScreen(),
          ],
        ),
      ),
    );
  }
}
