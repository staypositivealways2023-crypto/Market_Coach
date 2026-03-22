import 'package:flutter/material.dart';

// ─── Learn screen enums ────────────────────────────────────────────────────────

enum ProgressFilter { all, completed, inProgress, notStarted, bookmarked }

enum LevelFilter { all, beginner, intermediate, advanced }

const levelOrder = {
  'beginner': 0,
  'intermediate': 1,
  'advanced': 2,
};

// ─── Learn screen color palette ───────────────────────────────────────────────
// Single source of truth for all learn screen widgets.

const kLearnBg = Color(0xFF081120);
const kLearnSurface = Color(0xFF0F1B2D);
const kLearnCard = Color(0xFF132238);
const kLearnAccent = Color(0xFF22C7F0);
const kLearnAccentBlue = Color(0xFF2F80ED);
const kLearnTextPrimary = Color(0xFFF5F7FA);
const kLearnTextSecondary = Color(0xFF94A3B8);
const kLearnBorder = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
const kLearnSuccess = Color(0xFF22C55E);
const kLearnBeginnerColor = Color(0xFF22C7F0);
const kLearnIntermediateColor = Color(0xFFF59E0B);
const kLearnExpertColor = Color(0xFFEF4444);
