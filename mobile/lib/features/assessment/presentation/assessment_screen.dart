import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/choice_tile.dart';
import '../data/assessment_repository.dart';
import '../domain/questionnaire.dart';

/// The self-check: an intro, then one question per page.
class AssessmentScreen extends ConsumerStatefulWidget {
  const AssessmentScreen({this.afterOnboarding = false, super.key});

  /// When true, "Not now" continues into the app instead of going back.
  final bool afterOnboarding;

  @override
  ConsumerState<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends ConsumerState<AssessmentScreen> {
  final _answers = <String, int>{};

  /// -1 is the intro page.
  int _index = -1;
  bool _saving = false;

  void _leave() {
    if (!widget.afterOnboarding && context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  void _back() {
    if (_index <= -1) {
      _leave();
    } else {
      setState(() => _index--);
    }
  }

  Future<void> _answer(int value) async {
    final question = Questionnaire.questions[_index];
    setState(() => _answers[question.id] = value);
    if (_index < Questionnaire.questions.length - 1) {
      setState(() => _index++);
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await ref.read(assessmentRepositoryProvider).submit(_answers);
      if (mounted) context.pushReplacement(Routes.assessmentResult(result.id));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That didn't save. Please try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = Questionnaire.questions.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: _saving ? null : _back),
          title: Text(_index < 0 ? 'Self-check' : 'Question ${_index + 1} of $total'),
          bottom: _index < 0
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(value: (_index + 1) / total),
                ),
        ),
        body: SafeArea(child: _index < 0 ? _intro(context) : _question(context)),
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: AppSpacing.screen,
      children: [
        Text('A short self-check', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.md),
        Text(
          '${Questionnaire.questions.length} questions, about two minutes. It gives you a clearer picture of how '
          'gambling is affecting you right now, and some ideas for what might help.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Your answers stay on this phone. ${Questionnaire.disclaimer}',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(onPressed: () => setState(() => _index = 0), child: const Text('Start')),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: _leave, child: const Text('Not now')),
      ],
    );
  }

  Widget _question(BuildContext context) {
    final question = Questionnaire.questions[_index];
    final selected = _answers[question.id];
    return ListView(
      key: ValueKey(question.id),
      padding: AppSpacing.screen,
      children: [
        Semantics(header: true, child: Text(question.text, style: Theme.of(context).textTheme.headlineSmall)),
        const SizedBox(height: AppSpacing.lg),
        for (var value = 0; value < Questionnaire.answerOptions.length; value++)
          ChoiceTile(
            label: Questionnaire.answerOptions[value],
            selected: selected == value,
            onTap: _saving ? () {} : () => _answer(value),
          ),
        if (_saving) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
