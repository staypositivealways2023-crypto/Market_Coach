import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../models/order_book.dart';

class OrderBookWidget extends StatefulWidget {
  final String symbol;
  final bool isCrypto;
  final double? currentPrice;

  const OrderBookWidget({
    super.key,
    required this.symbol,
    required this.isCrypto,
    this.currentPrice,
  });

  @override
  State<OrderBookWidget> createState() => _OrderBookWidgetState();
}

class _OrderBookWidgetState extends State<OrderBookWidget> {
  OrderBook? _book;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  static const _bgCard = Color(0xFF111925);
  static const _bgRow  = Color(0xFF141C26);
  static const _green  = Color(0xFF26A69A);
  static const _red    = Color(0xFFEF5350);
  static const _label  = Color(0xFF8A95A3);

  @override
  void initState() {
    super.initState();
    _fetch();
    final interval = widget.isCrypto ? 3 : 15;
    _timer = Timer.periodic(Duration(seconds: interval), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final url = '${APIConfig.backendBaseUrl}/api/market/orderbook/${widget.symbol}?levels=10';
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _book = OrderBook.fromMap(data);
            _loading = false;
            _error = null;
          });
        }
      } else {
        if (mounted) setState(() { _loading = false; _error = 'Server ${resp.statusCode}'; });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_loading && _book == null)
            const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF12A28C))),
            )
          else if (_error != null && _book == null)
            _buildError()
          else if (_book != null)
            _buildBook(_book!),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final book = _book;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          const Text(
            'Order Book',
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          if (book != null && book.spread != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Spread ${_fmt(book.spread!)}  ${book.spreadPct?.toStringAsFixed(3) ?? '-'}%',
                style: const TextStyle(color: _label, fontSize: 9.5),
              ),
            ),
          ],
          const Spacer(),
          if (!widget.isCrypto)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'BBO only',
                style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(_error ?? 'Unknown error', style: const TextStyle(color: _label, fontSize: 11)),
    );
  }

  Widget _buildBook(OrderBook book) {
    final maxBidSize = book.bids.fold(0.0, (m, b) => b.size != null && b.size! > m ? b.size! : m);
    final maxAskSize = book.asks.fold(0.0, (m, a) => a.size != null && a.size! > m ? a.size! : m);
    final maxSize = maxBidSize > maxAskSize ? maxBidSize : maxAskSize;

    return Column(
      children: [
        // ── Pressure bar ───────────────────────────────────────────────────
        _buildPressureBar(book),
        const SizedBox(height: 6),

        // ── Column headers ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(child: Text('Size', style: TextStyle(color: _label, fontSize: 9.5), textAlign: TextAlign.left)),
              Expanded(child: Text('Bid', style: TextStyle(color: _green, fontSize: 9.5), textAlign: TextAlign.right)),
              const SizedBox(width: 8),
              Expanded(child: Text('Ask', style: TextStyle(color: _red, fontSize: 9.5), textAlign: TextAlign.left)),
              Expanded(child: Text('Size', style: TextStyle(color: _label, fontSize: 9.5), textAlign: TextAlign.right)),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // ── Book rows ───────────────────────────────────────────────────────
        ...List.generate(
          _rowCount(book),
          (i) => _buildRow(book, i, maxSize),
        ),

        // ── Current price indicator ─────────────────────────────────────────
        if (widget.currentPrice != null)
          _buildCurrentPriceRow(widget.currentPrice!),

        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildPressureBar(OrderBook book) {
    final buyPct = book.buyPressurePct.clamp(0.0, 100.0);
    final sellPct = 100.0 - buyPct;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${buyPct.toStringAsFixed(1)}% Buy',
                style: const TextStyle(color: _green, fontSize: 10, fontWeight: FontWeight.w600),
              ),
              Text(
                '${sellPct.toStringAsFixed(1)}% Sell',
                style: const TextStyle(color: _red, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: Row(
                children: [
                  Expanded(
                    flex: buyPct.round(),
                    child: Container(color: _green.withValues(alpha: 0.75)),
                  ),
                  Expanded(
                    flex: sellPct.round(),
                    child: Container(color: _red.withValues(alpha: 0.75)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(OrderBook book, int i, double maxSize) {
    final bid = i < book.bids.length ? book.bids[i] : null;
    final ask = i < book.asks.length ? book.asks[i] : null;

    final bidFrac = (bid?.size != null && maxSize > 0) ? (bid!.size! / maxSize) : 0.0;
    final askFrac = (ask?.size != null && maxSize > 0) ? (ask!.size! / maxSize) : 0.0;

    return Container(
      height: 22,
      margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 6),
      decoration: BoxDecoration(
        color: _bgRow,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          // Bid side
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Volume bar (right-aligned, green)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  left: 0,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: bidFrac,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.15),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            bottomLeft: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Labels
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        bid?.size != null ? _fmtSize(bid!.size!) : '',
                        style: const TextStyle(color: _label, fontSize: 9.5),
                      ),
                      Text(
                        bid != null ? _fmt(bid.price) : '',
                        style: const TextStyle(color: _green, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Container(width: 1, color: Colors.white.withValues(alpha: 0.06)),

          // Ask side
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Volume bar (left-aligned, red)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: askFrac,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _red.withValues(alpha: 0.15),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(3),
                            bottomRight: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Labels
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        ask != null ? _fmt(ask.price) : '',
                        style: const TextStyle(color: _red, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        ask?.size != null ? _fmtSize(ask!.size!) : '',
                        style: const TextStyle(color: _label, fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPriceRow(double price) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFF12A28C), thickness: 0.5)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF12A28C).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF12A28C).withValues(alpha: 0.5)),
            ),
            child: Text(
              _fmt(price),
              style: const TextStyle(
                color: Color(0xFF12A28C),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider(color: Color(0xFF12A28C), thickness: 0.5)),
        ],
      ),
    );
  }

  int _rowCount(OrderBook book) {
    final n = book.bids.length > book.asks.length ? book.bids.length : book.asks.length;
    return n.clamp(0, 10);
  }

  String _fmt(double price) {
    if (price >= 1000) return price.toStringAsFixed(2);
    if (price >= 1)    return price.toStringAsFixed(3);
    return price.toStringAsFixed(5);
  }

  String _fmtSize(double size) {
    if (size >= 1000000) return '${(size / 1000000).toStringAsFixed(2)}M';
    if (size >= 1000)    return '${(size / 1000).toStringAsFixed(2)}K';
    if (size >= 1)       return size.toStringAsFixed(2);
    return size.toStringAsFixed(4);
  }
}
