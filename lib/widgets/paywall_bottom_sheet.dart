import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/subscription_provider.dart';
import 'glass_card.dart';

// Loading state notifier for the paywall buttons
final _paywallLoadingProvider = StateProvider<bool>((ref) => false);

/// Shows a Pro upgrade prompt.
/// Call via: showModalBottomSheet(builder: (_) => const PaywallBottomSheet())
class PaywallBottomSheet extends ConsumerWidget {
  const PaywallBottomSheet({super.key});

  static const _cyan = Color(0xFF06B6D4);
  static const _purple = Color(0xFF8B5CF6);

  static const _features = [
    (Icons.chat_outlined, 'Unlimited AI conversations'),
    (Icons.bar_chart, 'Full signal analysis on every stock'),
    (Icons.insights, 'AI trade debrief after every paper trade'),
    (Icons.pie_chart_outline, 'Portfolio AI analysis'),
    (Icons.notifications_outlined, 'Daily market brief notifications'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_cyan, _purple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),

          const Text(
            'Upgrade to Pro',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_cyan, _purple]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '\$9.99 / month',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Feature list
          ..._features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(f.$1, color: _cyan, size: 17),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    f.$2,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Get Pro button
          Consumer(
            builder: (context, ref, _) {
              final isLoading = ref.watch(_paywallLoadingProvider);
              return SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final service = ref.read(subscriptionServiceProvider);
                          if (service == null) return;
                          ref.read(_paywallLoadingProvider.notifier).state = true;
                          try {
                            await service.upgradeToPro();
                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Purchase failed: $e'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          } finally {
                            ref.read(_paywallLoadingProvider.notifier).state =
                                false;
                          }
                        },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: _cyan,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Get Pro — \$9.99 / month',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),

          // Restore purchases
          Consumer(
            builder: (context, ref, _) {
              return TextButton(
                onPressed: () async {
                  final service = ref.read(subscriptionServiceProvider);
                  if (service == null) return;
                  final restored = await service.restorePurchases();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(restored
                          ? '✅ Pro subscription restored!'
                          : 'No previous purchase found.'),
                    ));
                    if (restored) Navigator.pop(context);
                  }
                },
                child: Text(
                  'Restore purchase',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),

          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Maybe later',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}
