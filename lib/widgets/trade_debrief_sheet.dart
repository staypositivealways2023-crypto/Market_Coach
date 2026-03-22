import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/signal_analysis.dart';
import '../providers/subscription_provider.dart';
import '../services/backend_service.dart';
import 'disclaimer_banner.dart';
import 'glass_card.dart';

/// Bottom sheet shown after a paper trade completes.
/// Calls Claude API (non-streaming, max 200 tokens) for a brief debrief.
class TradeDebriefSheet extends ConsumerStatefulWidget {
  final String symbol;
  final String name;
  final bool isBuy;
  final double shares;
  final double price;
  final double totalValue;
  final SignalAnalysis? signalAnalysis;

  const TradeDebriefSheet({
    super.key,
    required this.symbol,
    required this.name,
    required this.isBuy,
    required this.shares,
    required this.price,
    required this.totalValue,
    this.signalAnalysis,
  });

  @override
  ConsumerState<TradeDebriefSheet> createState() => _TradeDebriefSheetState();
}

class _TradeDebriefSheetState extends ConsumerState<TradeDebriefSheet> {
  String? _debriefText;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sub = ref.read(subscriptionProvider).valueOrNull;
    if (sub != null && sub.isAtLimit) {
      setState(() { _debriefText = null; _loading = false; });
      return;
    }
    try {
      final text = await _callClaude();
      if (mounted) setState(() { _debriefText = text; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Debrief unavailable'; _loading = false; });
    }
  }

  Future<String> _callClaude() async {
    final action = widget.isBuy ? 'BUY' : 'SELL';
    final sig = widget.signalAnalysis;
    final text = await BackendService().getTradeDebrief(
      symbol: widget.symbol,
      action: action,
      shares: widget.shares,
      price: widget.price,
      compositeScore: sig?.compositeScore,
      trend: sig?.signals.candlestick.signal,
    );
    if (text == null) throw Exception('Debrief unavailable');
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    final isAtLimit = sub?.isAtLimit ?? false;
    final accent = widget.isBuy ? const Color(0xFF10B981) : Colors.redAccent;
    final label = widget.isBuy ? 'BUY' : 'SELL';

    return GlassCard(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // BUY/SELL badge header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Trade Debrief',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Trade summary
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _InfoCell(label: 'Symbol', value: widget.symbol),
                _InfoCell(
                  label: 'Shares',
                  value: widget.shares.toStringAsFixed(4),
                ),
                _InfoCell(
                  label: 'Price',
                  value: '\$${widget.price.toStringAsFixed(2)}',
                ),
                _InfoCell(
                  label: 'Total',
                  value: '\$${widget.totalValue.toStringAsFixed(2)}',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),

          // AI debrief content
          if (isAtLimit && !_loading) ...[
            _LockedMessage(),
          ] else if (_loading) ...[
            const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06B6D4)),
                ),
                SizedBox(width: 12),
                Text('Analysing your trade…',
                    style: TextStyle(color: Colors.white60, fontSize: 13)),
              ],
            ),
          ] else if (_error != null) ...[
            Text(_error!,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ] else if (_debriefText != null) ...[
            AiTextBlock(
              child: Text(
                _debriefText!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          const DisclaimerBanner(),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  const _InfoCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _LockedMessage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.lock_outline, color: Colors.white38, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Upgrade to Pro for AI trade debriefs.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
