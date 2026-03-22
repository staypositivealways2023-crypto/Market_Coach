import 'package:flutter/material.dart';

/// Single-line educational disclaimer footer.
/// Reused in Chat, Analysis, and Trade Debrief.
class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 13, color: Colors.amber),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'For educational purposes only. Not financial advice.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.55),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
