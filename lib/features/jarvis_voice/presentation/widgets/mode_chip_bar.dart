import 'package:flutter/material.dart';

import '../../data/models/voice_session_bootstrap.dart';

/// Row of mode chips: General | Lesson | Trade Debrief.
/// Disabled while a session is connected (mode is locked during a session).
class ModeChipBar extends StatelessWidget {
  final VoiceMode selected;
  final ValueChanged<VoiceMode> onSelected;
  final bool enabled;

  const ModeChipBar({
    super.key,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: VoiceMode.values.map((mode) {
          final isSelected = mode == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(mode.displayLabel),
              selected: isSelected,
              onSelected: enabled ? (_) => onSelected(mode) : null,
              backgroundColor: const Color(0xFF111925),
              selectedColor: const Color(0xFF12A28C).withValues(alpha: 0.2),
              checkmarkColor: const Color(0xFF12A28C),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFF12A28C) : Colors.white54,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              side: BorderSide(
                color: isSelected ? const Color(0xFF12A28C) : Colors.white12,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
