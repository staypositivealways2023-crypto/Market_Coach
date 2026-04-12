import 'package:flutter/material.dart';

enum MicState { idle, loading, listening, speaking }

/// Animated mic button that morphs between session states.
///
/// idle     → grey mic icon, tap to start
/// loading  → circular progress indicator (connecting to backend)
/// listening → red pulsing circle with mic icon (user speaking)
/// speaking  → green pulsing circle with speaker icon (assistant speaking)
class MicButton extends StatefulWidget {
  final MicState micState;
  final VoidCallback onTap;

  const MicButton({
    super.key,
    required this.micState,
    required this.onTap,
  });

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAnimating = widget.micState == MicState.listening ||
        widget.micState == MicState.speaking;

    Widget inner;
    Color bgColor;
    IconData icon;

    switch (widget.micState) {
      case MicState.loading:
        bgColor = Colors.grey.shade800;
        inner = const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white,
          ),
        );
        icon = Icons.mic; // fallback, not shown
        break;
      case MicState.listening:
        bgColor = const Color(0xFFE53935);
        icon = Icons.mic;
        inner = Icon(icon, color: Colors.white, size: 32);
        break;
      case MicState.speaking:
        bgColor = const Color(0xFF12A28C);
        icon = Icons.volume_up_rounded;
        inner = Icon(icon, color: Colors.white, size: 32);
        break;
      case MicState.idle:
        bgColor = Colors.grey.shade700;
        icon = Icons.mic_none_rounded;
        inner = Icon(icon, color: Colors.white70, size: 32);
        break;
    }

    Widget button = GestureDetector(
      onTap: widget.micState == MicState.loading ? null : widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          boxShadow: isAnimating
              ? [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 4,
                  )
                ]
              : [],
        ),
        child: Center(
          child: widget.micState == MicState.loading ? inner : inner,
        ),
      ),
    );

    if (isAnimating) {
      button = ScaleTransition(scale: _scale, child: button);
    }

    return button;
  }
}
