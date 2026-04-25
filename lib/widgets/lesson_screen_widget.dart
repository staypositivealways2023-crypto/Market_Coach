import 'package:flutter/material.dart';
import '../models/lesson_screen.dart';

/// Renders different lesson screen types based on [LessonScreen.type].
///
/// Supported screen types:
/// - **`intro`**: Title screen with icon, title, and subtitle
///   - Content: `icon` (string, icon name)
///
/// - **`text`**: Rich text content with optional title/subtitle
///   - Content: `body` (string, main text content)
///
/// - **`diagram`**: Image with caption
///   - Content: `imageUrl` (string), `caption` (string, optional)
///
/// - **`quiz_single`**: Interactive single-choice quiz with feedback
///   - Content: `question` (string), `options` (list), `correctIndex` (int), `explanation` (string)
///
/// - **`bullets`**: Bullet point list with optional title/subtitle
///   - Content: `items` (list of strings)
///
/// - **`takeaways`**: Numbered key takeaways with optional title/subtitle
///   - Content: `items` (list of strings)
///
/// Unsupported types show an error widget with the type name.
///
/// Example usage:
/// ```dart
/// LessonScreenWidget(screen: lessonScreen)
/// ```
class LessonScreenWidget extends StatelessWidget {
  const LessonScreenWidget({
    super.key,
    required this.screen,
    this.onQuizAnswered,
    this.onQuizPassed,
  });

  final LessonScreen screen;
  final Function(bool isCorrect)? onQuizAnswered;
  final VoidCallback? onQuizPassed;

  @override
  Widget build(BuildContext context) {
    switch (screen.type) {
      case 'intro':
        return _IntroScreen(screen: screen);
      case 'text':
        return _TextScreen(screen: screen);
      case 'diagram':
        return _DiagramScreen(screen: screen);
      case 'quiz_single':
        return _QuizSingleScreen(
          screen: screen,
          onAnswered: onQuizAnswered,
          onPassed: onQuizPassed,
        );
      case 'quiz_multi':
        // TODO: Implement multi-choice quiz widget
        return _UnsupportedScreen(type: 'quiz_multi (coming soon)');
      case 'bullets':
        return _BulletsScreen(screen: screen);
      case 'takeaways':
        return _TakeawaysScreen(screen: screen);
      default:
        return _UnsupportedScreen(type: screen.type);
    }
  }
}

// INTRO SCREEN
class _IntroScreen extends StatelessWidget {
  const _IntroScreen({required this.screen});
  final LessonScreen screen;

  @override
  Widget build(BuildContext context) {
    final content = screen.content;
    final icon = content['icon'] as String? ?? 'school';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getIconData(icon),
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              screen.title ?? '',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            if (screen.subtitle != null) ...[
              const SizedBox(height: 16),
              Text(
                screen.subtitle!,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getIconData(String name) {
    switch (name) {
      case 'school':
        return Icons.school;
      case 'lightbulb':
        return Icons.lightbulb_outline;
      case 'chart':
      case 'show_chart':
        return Icons.show_chart;
      case 'quiz':
        return Icons.quiz_outlined;
      case 'trending_up':
        return Icons.trending_up;
      case 'attach_money':
        return Icons.attach_money;
      case 'horizontal_rule':
        return Icons.horizontal_rule;
      case 'calculate':
        return Icons.calculate;
      default:
        return Icons.article_outlined;
    }
  }
}

// TEXT SCREEN
class _TextScreen extends StatelessWidget {
  const _TextScreen({required this.screen});
  final LessonScreen screen;

  @override
  Widget build(BuildContext context) {
    final content = screen.content;
    final body = content['body'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (screen.title != null) ...[
            Text(
              screen.title!,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
          ],
          Text(body, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

// DIAGRAM SCREEN
class _DiagramScreen extends StatelessWidget {
  const _DiagramScreen({required this.screen});
  final LessonScreen screen;

  @override
  Widget build(BuildContext context) {
    final content = screen.content;
    final imageUrl = content['imageUrl'] as String?;
    final caption = content['caption'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (screen.title != null) ...[
            Text(
              screen.title!,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
          ],
          Container(
            width: double.infinity,
            height: 300,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image, size: 48),
                      ),
                    ),
                  )
                : const Center(child: Icon(Icons.image_outlined, size: 48)),
          ),
          if (caption != null) ...[
            const SizedBox(height: 12),
            Text(
              caption,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// QUIZ SINGLE SCREEN
class _QuizSingleScreen extends StatefulWidget {
  const _QuizSingleScreen({
    required this.screen,
    this.onAnswered,
    this.onPassed,
  });
  final LessonScreen screen;
  final Function(bool isCorrect)? onAnswered;
  final VoidCallback? onPassed;

  @override
  State<_QuizSingleScreen> createState() => _QuizSingleScreenState();
}

class _QuizSingleScreenState extends State<_QuizSingleScreen> {
  int? _selectedIndex;
  bool _showAnswer = false;

  @override
  Widget build(BuildContext context) {
    final content = widget.screen.content ?? {};
    final question = content['question'] as String? ?? '';
    final options =
        (content['options'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final correctIndex = (content['correctIndex'] as num?)?.toInt() ?? 0;
    final explanation = content['explanation'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          ...List.generate(options.length, (index) {
            final isSelected = _selectedIndex == index;
            final isCorrect = index == correctIndex;
            final showCorrect = _showAnswer && isCorrect;
            final showIncorrect = _showAnswer && isSelected && !isCorrect;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Material(
                color: showCorrect
                    ? Colors.green.withOpacity(0.2)
                    : showIncorrect
                    ? Colors.red.withOpacity(0.2)
                    : isSelected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _showAnswer
                      ? null
                      : () => setState(() => _selectedIndex = index),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: showCorrect
                            ? Colors.green
                            : showIncorrect
                            ? Colors.red
                            : isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(options[index])),
                        if (showCorrect)
                          const Icon(Icons.check_circle, color: Colors.green),
                        if (showIncorrect)
                          const Icon(Icons.cancel, color: Colors.red),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          if (!_showAnswer && _selectedIndex != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  setState(() => _showAnswer = true);
                  if (_selectedIndex != null) {
                    final isCorrect = _selectedIndex == correctIndex;
                    widget.onAnswered?.call(isCorrect);
                    // Advance lesson if the answer was correct
                    if (isCorrect) widget.onPassed?.call();
                  }
                },
                child: const Text('Check Answer'),
              ),
            ),
          if (_showAnswer && explanation != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      explanation,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// BULLETS SCREEN
class _BulletsScreen extends StatelessWidget {
  const _BulletsScreen({required this.screen});
  final LessonScreen screen;

  @override
  Widget build(BuildContext context) {
    final content = screen.content ?? {};
    final raw = content['items'] ?? content['points'];
    final items =
        (raw as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (screen.title != null) ...[
            Text(
              screen.title!,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
          ],
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, right: 12),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// TAKEAWAYS SCREEN
class _TakeawaysScreen extends StatelessWidget {
  const _TakeawaysScreen({required this.screen});
  final LessonScreen screen;

  @override
  Widget build(BuildContext context) {
    final content = screen.content ?? {};
    final raw = content['items'] ?? content['points'];
    final items =
        (raw as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb,
                color: Theme.of(context).colorScheme.primary,
                size: 32,
              ),
              const SizedBox(width: 12),
              Text(
                screen.title ?? 'Key Takeaways',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: 24),
          ...items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// UNSUPPORTED SCREEN
class _UnsupportedScreen extends StatelessWidget {
  const _UnsupportedScreen({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64),
          const SizedBox(height: 16),
          Text(
            'Unsupported screen type: $type',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
