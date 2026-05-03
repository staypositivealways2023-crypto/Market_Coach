// Analyst Graph response model
// Mirrors the LangGraph AnalystState returned by POST /api/analyst/query
// Created for Phase 8 — Flutter Integration

/// One scenario case from the synthesis node.
/// Fields are plain strings because the LLM returns them as human-readable text.
class AnalystScenarioCard {
  final String title;
  final String trigger;
  final String target;
  final String probability;

  const AnalystScenarioCard({
    required this.title,
    required this.trigger,
    required this.target,
    required this.probability,
  });

  factory AnalystScenarioCard.fromJson(Map<String, dynamic> json) {
    return AnalystScenarioCard(
      title:       json['title']       as String? ?? '',
      trigger:     json['trigger']     as String? ?? '',
      target:      json['target']      as String? ?? '',
      probability: json['probability'] as String? ?? '',
    );
  }

  /// True if all fields are populated and meaningful.
  bool get isPopulated =>
      title.isNotEmpty && trigger.isNotEmpty && target.isNotEmpty;
}

/// Bull / Base / Bear scenario triple from synthesis node.
class AnalystScenarios {
  final AnalystScenarioCard bull;
  final AnalystScenarioCard base;
  final AnalystScenarioCard bear;

  const AnalystScenarios({
    required this.bull,
    required this.base,
    required this.bear,
  });

  factory AnalystScenarios.fromJson(Map<String, dynamic> json) {
    return AnalystScenarios(
      bull: AnalystScenarioCard.fromJson(
          (json['bull'] as Map<String, dynamic>?) ?? {}),
      base: AnalystScenarioCard.fromJson(
          (json['base'] as Map<String, dynamic>?) ?? {}),
      bear: AnalystScenarioCard.fromJson(
          (json['bear'] as Map<String, dynamic>?) ?? {}),
    );
  }
}

/// Full response from the LangGraph analyst pipeline (all 5 nodes).
class AnalystResponse {
  // ── Input echo ─────────────────────────────────────────────────────────────
  final String intent; // technical | fundamental | sentiment | general
  final String? symbol;

  // ── Phase 3: Reasoning (DeepSeek-R1 14B) ───────────────────────────────────
  final String? cotThinking;     // <think>...</think> content — shown collapsed
  final String? reasoningAnswer; // Final answer without think block

  // ── Phase 4: Verification (Claude Sonnet) ──────────────────────────────────
  final bool? verificationPassed;
  final double? verificationScore; // 0.0 – 1.0
  final List<String> flaggedClaims;

  // ── Phase 5: Synthesis (Mistral 7B + Cartesia TTS) ─────────────────────────
  final String? coachResponse;       // Dean's 3–4 sentence verdict
  final AnalystScenarios? scenarioCards; // Bull / Base / Bear
  final String? audioUrl;            // relative path e.g. /api/analyst/audio/{id}

  // ── Error state ─────────────────────────────────────────────────────────────
  final String? error;

  const AnalystResponse({
    required this.intent,
    this.symbol,
    this.cotThinking,
    this.reasoningAnswer,
    this.verificationPassed,
    this.verificationScore,
    this.flaggedClaims = const [],
    this.coachResponse,
    this.scenarioCards,
    this.audioUrl,
    this.error,
  });

  factory AnalystResponse.fromJson(Map<String, dynamic> json) {
    // Parse scenario cards — may be null or an empty map if synthesis failed
    AnalystScenarios? scenarios;
    final rawScenarios = json['scenario_cards'];
    if (rawScenarios is Map<String, dynamic> && rawScenarios.isNotEmpty) {
      try {
        scenarios = AnalystScenarios.fromJson(rawScenarios);
      } catch (_) {
        // Malformed scenario JSON — treat as absent
      }
    }

    return AnalystResponse(
      intent:              json['intent']               as String?  ?? 'general',
      symbol:              json['symbol']               as String?,
      cotThinking:         json['cot_thinking']         as String?,
      reasoningAnswer:     json['reasoning_answer']     as String?,
      verificationPassed:  json['verification_passed']  as bool?,
      verificationScore:   (json['verification_score']  as num?)?.toDouble(),
      flaggedClaims:       (json['flagged_claims']       as List<dynamic>?)
                               ?.cast<String>() ?? const [],
      coachResponse:       json['coach_response']       as String?,
      scenarioCards:       scenarios,
      audioUrl:            json['audio_url']            as String?,
      error:               json['error']                as String?,
    );
  }

  /// True when the verification node explicitly flagged the analysis.
  bool get isVerificationWarning =>
      verificationPassed == false && flaggedClaims.isNotEmpty;

  /// True when there is CoT content worth showing.
  bool get hasThinking =>
      cotThinking != null && cotThinking!.trim().isNotEmpty;

  /// True when Dean's coach text is available.
  bool get hasCoachResponse =>
      coachResponse != null && coachResponse!.trim().isNotEmpty;
}
