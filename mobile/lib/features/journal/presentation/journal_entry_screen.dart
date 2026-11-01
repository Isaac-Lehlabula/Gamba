import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../data/journal_repository.dart';
import '../domain/journal_models.dart';

/// Write a new journal entry ([entryId] null) or edit one. Every field is optional; an entry
/// just needs something in it.
class JournalEntryScreen extends ConsumerWidget {
  const JournalEntryScreen({this.entryId, super.key});

  final String? entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entryId == null) return const _JournalForm(existing: null);
    return switch (ref.watch(journalEntryProvider(entryId!))) {
      AsyncData(value: final e?) => _JournalForm(existing: e),
      AsyncData() || AsyncError() => Scaffold(appBar: AppBar(), body: const Center(child: Text('This entry is no longer on this phone.'))),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

class _JournalForm extends ConsumerStatefulWidget {
  const _JournalForm({required this.existing});

  final JournalEntry? existing;

  @override
  ConsumerState<_JournalForm> createState() => _JournalFormState();
}

class _JournalFormState extends ConsumerState<_JournalForm> {
  late final TextEditingController _note;
  late DateTime _at;
  int? _mood;
  TriggerType? _trigger;
  int? _intensity;
  JournalOutcome? _outcome;
  late Set<CopingStrategy> _helped;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;
  /// Urge questions only appear once the user says there was one.
  bool get _hadUrge => _outcome == JournalOutcome.resisted || _outcome == JournalOutcome.gambled;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _note = TextEditingController(text: e?.note ?? '');
    _at = e?.occurredAt ?? ref.read(clockProvider)();
    _mood = e?.mood;
    _trigger = e?.trigger;
    _intensity = e?.urgeIntensity;
    _outcome = e?.outcome;
    _helped = {...?e?.helped};
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  JournalInput get _input => JournalInput(
        occurredAt: _at,
        mood: _mood,
        trigger: _hadUrge ? _trigger : null,
        urgeIntensity: _hadUrge ? _intensity : null,
        outcome: _outcome,
        helped: _hadUrge ? _helped : const {},
        note: _note.text,
      );

  Future<void> _save() async {
    if (_input.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Add how you feel, an urge, or a note first.')));
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(journalRepositoryProvider);
    if (_isEdit) {
      await repo.update(widget.existing!.id, _input);
    } else {
      await repo.add(_input);
    }
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('It will be removed from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(journalRepositoryProvider).delete(widget.existing!.id);
    if (mounted) context.pop();
  }

  Future<void> _pickTime() async {
    final now = ref.read(clockProvider)();
    final date = await showDatePicker(context: context, initialDate: _at, firstDate: DateTime(2000), lastDate: now);
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    final picked = DateTime(date.year, date.month, date.day, time?.hour ?? _at.hour, time?.minute ?? _at.minute);
    setState(() => _at = picked.isAfter(now) ? now : picked);
  }

  Widget _scale(String label, int? value, Map<int, String> ends, ValueChanged<int?> onChanged) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var v = 1; v <= 5; v++)
              ChoiceChip(
                label: Text('$v'),
                tooltip: ends[v],
                selected: value == v,
                onSelected: (selected) => onChanged(selected ? v : null),
              ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(ends[1]!, style: theme.textTheme.bodySmall), Text(ends[5]!, style: theme.textTheme.bodySmall)],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit entry' : 'New entry'),
        actions: [
          if (_isEdit) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: _saving ? null : _delete),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('When'),
              subtitle: Text(DateFormat('EEEE d MMMM, HH:mm').format(_at)),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _pickTime,
            ),
            const SizedBox(height: AppSpacing.md),
            _scale('How are you feeling?', _mood, MoodScale.labels, (v) => setState(() => _mood = v)),
            const SizedBox(height: AppSpacing.lg),
            Text('Was there an urge to gamble?', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final o in JournalOutcome.values)
                  ChoiceChip(label: Text(o.label), selected: _outcome == o, onSelected: (s) => setState(() => _outcome = s ? o : null)),
              ],
            ),
            if (_hadUrge) ...[
              const SizedBox(height: AppSpacing.lg),
              _scale('How strong was it?', _intensity, const {1: 'Mild', 5: 'Very strong'}, (v) => setState(() => _intensity = v)),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<TriggerType>(
                initialValue: _trigger,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'What set it off? (optional)'),
                items: [for (final t in TriggerType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                onChanged: (t) => setState(() => _trigger = t),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('What helped, or what did you try?', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final h in CopingStrategy.values)
                    FilterChip(
                      label: Text(h.label),
                      selected: _helped.contains(h),
                      onSelected: (s) => setState(() => s ? _helped.add(h) : _helped.remove(h)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _note,
              maxLength: maxJournalNoteLength,
              maxLines: 5,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Anything else (optional)', hintText: 'Only you can see this.'),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_isEdit ? 'Save changes' : 'Save')),
          ],
        ),
      ),
    );
  }
}
