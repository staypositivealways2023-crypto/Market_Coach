import 'package:flutter/material.dart';
import 'learn_constants.dart';

/// Slim horizontal AI Coach prompt card.
/// Positioned between the carousel and search bar to stay contextual
/// without dominating the screen.
class AiCoachBanner extends StatelessWidget {
  const AiCoachBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: GestureDetector(
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI Coach coming soon!'),
            duration: Duration(seconds: 2),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: kLearnAccent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kLearnAccent.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kLearnAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  color: kLearnAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Text
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ask AI Coach',
                      style: TextStyle(
                        color: kLearnTextPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Get personalized guidance on any topic',
                      style: TextStyle(
                        color: kLearnTextSecondary,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: kLearnAccent.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
