import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../tracker/domain/money.dart';
import '../data/goal_repository.dart';
import '../domain/goal_models.dart';

/// Create a goal ([goalId] null, optionally with a suggested [initialName]) or edit one.
class GoalFormScreen extends ConsumerWidget {
  const GoalFormScreen({this.goalId, this.initialName, super.key});

  final String? goalId;
  final String? initialName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (goalId == null) return _GoalForm(existing: null, initialName: initialName);
    return switch (ref.watch(goalProvider(goalId!))) {
      AsyncData(value: final goal?) => _GoalForm(existing: goal),
      AsyncData() || AsyncError() => Scaffold(appBar: AppBar(), body: const Center(child: Text('This goal is no longer on this phone.'))),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm({required this.existing, this.initialName});

  final RecoveryGoal? existing;
  final String? initialName;

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _target;
  late GoalCategory _category;
  DateTime? _targetDate;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _name = TextEditingController(text: g?.name ?? widget.initialName ?? '');
    _target = TextEditingController(text: g == null ? '' : '${g.targetCents ~/ 100}');
    _category = g?.category ?? GoalCategory.savings;
    _targetDate = g?.targetDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 30),
      helpText: 'When would you like to reach it?',
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final input = GoalInput(
      name: _name.text,
      category: _category,
      targetCents: parseRandsToCents(_target.text)!,
      targetDate: _targetDate,
    );
    final repo = ref.read(goalRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.updateGoal(widget.existing!.id, input);
        if (mounted) context.pop();
      } else {
        final id = await repo.addGoal(input);
        if (mounted) context.pushReplacement(Routes.goal(id));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That didn't save. Please try again.")));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this goal?'),
        content: const Text('The goal and the money counted toward it will be removed from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(goalRepositoryProvider).deleteGoal(widget.existing!.id);
    if (mounted) context.go(Routes.goals);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit goal' : 'New goal'),
        actions: [
          if (_isEdit) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: _saving ? null : _delete),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: AppSpacing.screen,
            children: [
              TextFormField(
                controller: _name,
                maxLength: maxGoalNameLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'What are you saving for?'),
                validator: (text) => (text ?? '').trim().isEmpty ? 'Give your goal a name' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Type of goal', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final c in GoalCategory.values)
                    ChoiceChip(label: Text(c.label), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _target,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Target amount', prefixText: 'R '),
                validator: (text) => parseRandsToCents(text ?? '') == null ? 'Enter an amount, like 20000' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Target date (optional)'),
                subtitle: Text(_targetDate == null ? 'No date' : DateFormat('d MMMM y').format(_targetDate!)),
                trailing: _targetDate == null
                    ? const Icon(Icons.edit_outlined)
                    : IconButton(icon: const Icon(Icons.clear), tooltip: 'Remove date', onPressed: () => setState(() => _targetDate = null)),
                onTap: _pickDate,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'Save changes' : 'Create goal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
