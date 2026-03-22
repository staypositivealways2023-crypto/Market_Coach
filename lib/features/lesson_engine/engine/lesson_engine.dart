import 'package:flutter/foundation.dart';
import '../models/lesson_step.dart';
import '../models/guided_lesson.dart';

/// Manages all mutable state for an active guided lesson session.
/// Owned by [GuidedLessonScreen] — lives exactly as long as the screen.
class LessonEngine extends ChangeNotifier {
  final GuidedLesson lesson;

  LessonEngine(this.lesson) {
    _timer.start();
  }

  // ─── State ────────────────────────────────────────────────────────────────
  int _currentIndex = 0;
  final Stopwatch _timer = Stopwatch();

  // MCQ state
  int? _selectedAnswer;
  bool? _answerCorrect;

  // TapToIdentify state (RSI zones)
  String? _tappedZoneId;
  bool? _tapCorrect;

  // TapOnChart state (ST-3: tapping a candle)
  int? _tappedCandleIndex;
  bool? _tapCandleCorrect;

  // RangeSlider state (ST-4)
  double _sliderValue = 50.0;
  bool _sliderSubmitted = false;
  bool? _sliderCorrect;

  // LabelMatch state (ST-5)
  final Map<String, String> _labelMatches = {}; // itemId → targetId
  bool _labelMatchComplete = false;

  // ─── Getters ──────────────────────────────────────────────────────────────
  int get currentIndex => _currentIndex;
  LessonStep get currentStep => lesson.steps[_currentIndex];
  bool get isLastStep => _currentIndex >= lesson.steps.length - 1;
  Duration get elapsed => _timer.elapsed;

  double get progress => lesson.steps.isEmpty
      ? 0.0
      : (_currentIndex + 1) / lesson.steps.length;

  // MCQ
  int? get selectedAnswer => _selectedAnswer;
  bool? get answerCorrect => _answerCorrect;

  // TapToIdentify
  String? get tappedZoneId => _tappedZoneId;
  bool? get tapCorrect => _tapCorrect;

  // TapOnChart
  int? get tappedCandleIndex => _tappedCandleIndex;
  bool? get tapCandleCorrect => _tapCandleCorrect;

  // RangeSlider
  double get sliderValue => _sliderValue;
  bool get sliderSubmitted => _sliderSubmitted;
  bool? get sliderCorrect => _sliderCorrect;

  // LabelMatch
  Map<String, String> get labelMatches => Map.unmodifiable(_labelMatches);
  bool get labelMatchComplete => _labelMatchComplete;

  /// Whether the "Continue" button is enabled for the current step.
  bool get canAdvance {
    return switch (currentStep) {
      MultipleChoiceStep() => _selectedAnswer != null,
      TapToIdentifyStep() => _tapCorrect == true,
      TapOnChartStep() => _tapCandleCorrect == true,
      RangeSliderQuizStep() => _sliderSubmitted,
      LabelMatchStep() => _labelMatchComplete,
      _ => true,
    };
  }

  // ─── Interactions ─────────────────────────────────────────────────────────

  void selectAnswer(int index) {
    if (_selectedAnswer != null) return;
    final step = currentStep;
    if (step is! MultipleChoiceStep) return;
    _selectedAnswer = index;
    _answerCorrect = index == step.correctIndex;
    notifyListeners();
  }

  void tapZone(String zoneId) {
    if (_tapCorrect == true) return;
    final step = currentStep;
    if (step is! TapToIdentifyStep) return;
    _tappedZoneId = zoneId;
    _tapCorrect = zoneId == step.targetZone;
    notifyListeners();
  }

  void tapCandle(int index) {
    if (_tapCandleCorrect == true) return;
    final step = currentStep;
    if (step is! TapOnChartStep) return;
    _tappedCandleIndex = index;
    _tapCandleCorrect = index == step.correctIndex;
    notifyListeners();
  }

  void updateSlider(double value) {
    if (_sliderSubmitted) return;
    _sliderValue = value;
    notifyListeners();
  }

  void submitSlider() {
    if (_sliderSubmitted) return;
    final step = currentStep;
    if (step is! RangeSliderQuizStep) return;
    _sliderSubmitted = true;
    _sliderCorrect = _sliderValue >= step.correctMin && _sliderValue <= step.correctMax;
    notifyListeners();
  }

  void setLabelMatch(String itemId, String targetId) {
    if (_labelMatchComplete) return;
    // Remove any existing assignment of this target
    _labelMatches.removeWhere((k, v) => v == targetId && k != itemId);
    _labelMatches[itemId] = targetId;
    _checkLabelMatchComplete();
    notifyListeners();
  }

  void clearLabelMatch(String itemId) {
    _labelMatches.remove(itemId);
    _labelMatchComplete = false;
    notifyListeners();
  }

  void _checkLabelMatchComplete() {
    final step = currentStep;
    if (step is! LabelMatchStep) return;
    if (_labelMatches.length < step.items.length) {
      _labelMatchComplete = false;
      return;
    }
    // All items must be assigned and correct
    bool allCorrect = step.correctMapping.entries.every(
      (e) => _labelMatches[e.key] == e.value,
    );
    _labelMatchComplete = allCorrect;
  }

  // ─── Navigation ───────────────────────────────────────────────────────────

  void advance() {
    if (!canAdvance) return;
    if (_currentIndex < lesson.steps.length - 1) {
      _currentIndex++;
      _resetStepState();
      notifyListeners();
    }
  }

  void goBack() {
    if (_currentIndex > 0) {
      _currentIndex--;
      _resetStepState();
      notifyListeners();
    }
  }

  void _resetStepState() {
    _selectedAnswer = null;
    _answerCorrect = null;
    _tappedZoneId = null;
    _tapCorrect = null;
    _tappedCandleIndex = null;
    _tapCandleCorrect = null;
    _sliderValue = 50.0;
    _sliderSubmitted = false;
    _sliderCorrect = null;
    _labelMatches.clear();
    _labelMatchComplete = false;
  }

  @override
  void dispose() {
    _timer.stop();
    super.dispose();
  }
}
