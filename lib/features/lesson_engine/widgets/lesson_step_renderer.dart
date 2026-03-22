import 'package:flutter/material.dart';
import '../models/lesson_step.dart';
import '../engine/lesson_engine.dart';
import 'steps/intro_step_widget.dart';
import 'steps/theory_step_widget.dart';
import 'steps/visual_explainer_widget.dart';
import 'steps/chart_highlight_widget.dart';
import 'steps/tap_to_identify_widget.dart';
import 'steps/multiple_choice_widget.dart';
import 'steps/compare_examples_widget.dart';
import 'steps/recap_step_widget.dart';
import 'steps/completion_step_widget.dart';
import 'steps/candlestick_demo_widget.dart';
import 'steps/indicator_demo_widget.dart';
import 'steps/tap_on_chart_widget.dart';
import 'steps/range_slider_quiz_widget.dart';
import 'steps/label_match_widget.dart';

/// Routes each [LessonStep] subtype to its corresponding widget.
/// Uses Dart 3 exhaustive sealed switch — compile error if a type is unhandled.
class LessonStepRenderer extends StatelessWidget {
  final LessonStep step;
  final LessonEngine engine;
  final void Function(bool isCorrect)? onAnswered;

  const LessonStepRenderer({
    super.key,
    required this.step,
    required this.engine,
    this.onAnswered,
  });

  @override
  Widget build(BuildContext context) {
    return switch (step) {
      IntroStep s => IntroStepWidget(step: s),
      TheoryStep s => TheoryStepWidget(step: s),
      VisualExplainerStep s => VisualExplainerWidget(step: s),
      ChartHighlightStep s => ChartHighlightWidget(step: s),
      TapToIdentifyStep s => TapToIdentifyWidget(step: s, engine: engine),
      MultipleChoiceStep s => MultipleChoiceWidget(step: s, engine: engine, onAnswered: onAnswered),
      CompareExamplesStep s => CompareExamplesWidget(step: s),
      RecapStep s => RecapStepWidget(step: s),
      CompletionStep s => CompletionStepWidget(step: s, engine: engine),
      CandlestickDemoStep s => CandlestickDemoWidget(step: s),
      IndicatorDemoStep s => IndicatorDemoWidget(step: s),
      TapOnChartStep s => TapOnChartWidget(step: s, engine: engine),
      RangeSliderQuizStep s => RangeSliderQuizWidget(step: s, engine: engine),
      LabelMatchStep s => LabelMatchWidget(step: s, engine: engine),
    };
  }
}
