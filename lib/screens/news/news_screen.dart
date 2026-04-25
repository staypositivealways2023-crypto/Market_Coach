import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/market_detail.dart';
import '../../providers/news_provider.dart';
import '../../widgets/glass_card.dart';

class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  Color _sentimentColor(String sentiment) {
    switch (sentiment.toLowerCase()) {
      case 'positive':
      case 'bullish':
        return const Color(0xFF0C9E6A);
      case 'negative':
      case 'bearish':
        return const Color(0xFFCF3B2E);
      default:
        return const Color(0xFF4D5BD6);
    }
  }

  String _sentimentLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'positive':
        return 'Bullish';
      case 'negative':
        return 'Bearish';
      default:
        return 'Neutral';
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final newsAsync = ref.watch(marketNewsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Market news',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Live indicator
                        newsAsync.when(
                          data: (_) => Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0C9E6A),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Live',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF0C9E6A),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Curated headlines with AI sentiment labels.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            newsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(Color(0xFF12A28C)),
                      ),
                      SizedBox(height: 16),
                      Text('Fetching latest news…',
                          style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
              ),

              error: (err, _) => SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            color: Colors.white38, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Could not load news',
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Check your connection and try again.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white54),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(marketNewsProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              data: (articles) => articles.isEmpty
                  ? const SliverFillRemaining(
                      child: Center(
                        child: Text('No news right now.',
                            style: TextStyle(color: Colors.white54)),
                      ),
                    )
                  : SliverList.builder(
                      itemCount: articles.length,
                      itemBuilder: (context, index) {
                        final NewsArticleItem item = articles[index];
                        final sentimentColor =
                            _sentimentColor(item.sentimentLabel);
                        return Padding(
                          padding:
                              const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          child: GlassCard(
                            padding: const EdgeInsets.all(16),
                            child: InkWell(
                              onTap: item.url.isNotEmpty
                                  ? () => _openUrl(item.url)
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        item.source,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: Colors.white70),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 4,
                                        height: 4,
                                        decoration: const BoxDecoration(
                                          color: Colors.white24,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        item.formattedDate,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: Colors.white54),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 4),
                                        decoration: ShapeDecoration(
                                          color: sentimentColor
                                              .withOpacity(0.12),
                                          shape: const StadiumBorder(),
                                        ),
                                        child: Text(
                                          _sentimentLabel(
                                              item.sentimentLabel),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: sentimentColor,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    item.title,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700),
                                  ),
                                  if (item.description != null &&
                                      item.description!.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      item.description!,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        color: Colors.white70,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                  if (item.url.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        const Spacer(),
                                        Text(
                                          'Read more →',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color:
                                                const Color(0xFF12A28C),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
