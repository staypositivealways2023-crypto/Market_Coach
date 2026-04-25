import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/quote.dart';
import '../../models/stock_summary.dart';
import '../../services/quote_service.dart';
import '../../utils/crypto_helper.dart';
import '../../widgets/glass_card.dart';
import '../../features/chart/screens/asset_chart_screen.dart';

enum SortCriteria { price, changePercent, volume, marketCap, name }

class MarketViewAllScreen extends StatefulWidget {
  final List<StockSummary> assets;
  final bool isCrypto;

  const MarketViewAllScreen({
    super.key,
    required this.assets,
    required this.isCrypto,
  });

  @override
  State<MarketViewAllScreen> createState() => _MarketViewAllScreenState();
}

class _MarketViewAllScreenState extends State<MarketViewAllScreen> {
  final _searchController = TextEditingController();
  final _binanceService = BinanceQuoteService();
  StreamSubscription<Map<String, Quote>>? _cryptoSubscription;
  Map<String, Quote> _cryptoQuotes = {};

  SortCriteria _sortBy = SortCriteria.changePercent;
  bool _ascending = false;
  String _searchQuery = '';
  List<StockSummary> _filteredAssets = [];

  @override
  void initState() {
    super.initState();
    _filteredAssets = widget.assets;

    // Stream live quotes for crypto
    if (widget.isCrypto) {
      final cryptoSymbols = widget.assets
          .map((a) => a.ticker)
          .where((symbol) => isCryptoSymbol(symbol))
          .toSet();

      if (cryptoSymbols.isNotEmpty) {
        _cryptoSubscription = _binanceService.streamQuotes(cryptoSymbols).listen((quotes) {
          if (mounted) {
            setState(() {
              _cryptoQuotes = quotes;
              _applyFilters();
            });
          }
        });
      }
    }

    _applyFilters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cryptoSubscription?.cancel();
    _binanceService.dispose();
    super.dispose();
  }

  void _applyFilters() {
    setState(() {
      // Filter by search query
      _filteredAssets = widget.assets.where((asset) {
        if (_searchQuery.isEmpty) return true;
        final query = _searchQuery.toLowerCase();
        return asset.ticker.toLowerCase().contains(query) ||
            asset.name.toLowerCase().contains(query);
      }).toList();

      // Sort
      _filteredAssets.sort((a, b) {
        // Get live prices for crypto
        final aPrice = _cryptoQuotes[a.ticker]?.price ?? a.price;
        final bPrice = _cryptoQuotes[b.ticker]?.price ?? b.price;
        final aChange = _cryptoQuotes[a.ticker]?.changePercent ?? a.changePercent;
        final bChange = _cryptoQuotes[b.ticker]?.changePercent ?? b.changePercent;

        int comparison = 0;
        switch (_sortBy) {
          case SortCriteria.price:
            comparison = aPrice.compareTo(bPrice);
            break;
          case SortCriteria.changePercent:
            comparison = aChange.compareTo(bChange);
            break;
          case SortCriteria.name:
            comparison = a.name.compareTo(b.name);
            break;
          case SortCriteria.volume:
          case SortCriteria.marketCap:
            // TODO: Add volume/market cap data to model
            comparison = 0;
            break;
        }

        return _ascending ? comparison : -comparison;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isCrypto ? 'All Crypto' : 'All Stocks'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Filter Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Search Field
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by ticker or name...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _searchQuery = '';
                              _applyFilters();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  onChanged: (value) {
                    _searchQuery = value;
                    _applyFilters();
                  },
                ),
                const SizedBox(height: 12),

                // Sort Controls
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<SortCriteria>(
                        initialValue: _sortBy,
                        decoration: InputDecoration(
                          labelText: 'Sort by',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: SortCriteria.changePercent,
                            child: Text('Change %'),
                          ),
                          DropdownMenuItem(
                            value: SortCriteria.price,
                            child: Text('Price'),
                          ),
                          DropdownMenuItem(
                            value: SortCriteria.name,
                            child: Text('Name'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _sortBy = value;
                            _applyFilters();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
                      onPressed: () {
                        setState(() {
                          _ascending = !_ascending;
                          _applyFilters();
                        });
                      },
                      tooltip: _ascending ? 'Ascending' : 'Descending',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Results Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${_filteredAssets.length} ${_filteredAssets.length == 1 ? 'result' : 'results'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Asset List
          Expanded(
            child: _filteredAssets.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.white38,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No assets found',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try a different search term',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredAssets.length,
                    itemBuilder: (context, index) {
                      final asset = _filteredAssets[index];
                      final quote = _cryptoQuotes[asset.ticker];

                      // Use live quote if available
                      final price = quote?.price ?? asset.price;
                      final changePercent = quote?.changePercent ?? asset.changePercent;
                      final isPositive = changePercent >= 0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AssetListTile(
                          asset: asset,
                          price: price,
                          changePercent: changePercent,
                          isPositive: isPositive,
                          isCrypto: widget.isCrypto,
                          isLive: quote != null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AssetListTile extends StatelessWidget {
  final StockSummary asset;
  final double price;
  final double changePercent;
  final bool isPositive;
  final bool isCrypto;
  final bool isLive;

  const _AssetListTile({
    required this.asset,
    required this.price,
    required this.changePercent,
    required this.isPositive,
    required this.isCrypto,
    required this.isLive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final changeColor = isPositive ? Colors.greenAccent : Colors.redAccent;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AssetChartScreen(
              stock: asset.copyWith(
                price: price,
                changePercent: changePercent,
              ),
            ),
          ),
        );
      },
      child: Row(
        children: [
          // Ticker & Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      asset.ticker,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isLive) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  asset.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Price & Change
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price > 0 ? '\$${price.toStringAsFixed(price < 1 ? 4 : 2)}' : '—',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: changeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                      color: changeColor,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${isPositive ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: changeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right,
            color: Colors.white54,
            size: 20,
          ),
        ],
      ),
    );
  }
}
