import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/data/profile_repository.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../data/tracker_repository.dart';
import '../domain/money.dart';

/// Add a new entry ([entryId] null) or edit an existing one.
class EntryFormScreen extends ConsumerWidget {
  const EntryFormScreen({this.entryId, super.key});

  final String? entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entryId == null) return const _EntryForm(existing: null);

    return switch (ref.watch(gamblingEntryProvider(entryId!))) {
      AsyncData(value: final entry?) => _EntryForm(existing: entry),
      AsyncData() => Scaffold(appBar: AppBar(), body: const Center(child: Text('This entry is no longer on this phone.'))),
      AsyncError() => Scaffold(appBar: AppBar(), body: const Center(child: Text("This entry couldn't be loaded."))),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

class _EntryForm extends ConsumerStatefulWidget {
  const _EntryForm({required this.existing});

  final GamblingEntry? existing;

  @override
  ConsumerState<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends ConsumerState<_EntryForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late GamblingEntryType _type;
  late GamblingType _gamblingType;
  late DateTime _date;
  String _platform = '';
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final now = ref.read(clockProvider)();
    _type = e?.entryType ?? GamblingEntryType.deposit;
    _amount = TextEditingController(text: e == null ? '' : _amountText(e.amountCents));
    _notes = TextEditingController(text: e?.notes ?? '');
    _date = e?.occurredAt ?? now;
    _platform = e?.platformName ?? '';
    // Default to what the user said they gamble on most, so the common case is one tap less.
    _gamblingType = e?.gamblingType ??
        ref.read(latestOnboardingProvider).value?.gamblingTypes.firstOrNull ??
        GamblingType.sportsBetting;
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  static String _amountText(int cents) =>
      cents % 100 == 0 ? '${cents ~/ 100}' : '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'When did this happen?',
    );
    if (picked == null) return;
    final isToday = DateUtils.isSameDay(picked, now);
    // Today keeps the current time; past days use midday so the date can't slip across midnight.
    setState(() => _date = isToday ? now : DateTime(picked.year, picked.month, picked.day, 12));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final input = EntryInput(
      type: _type,
      amountCents: parseRandsToCents(_amount.text)!,
      occurredAt: _date,
      gamblingType: _gamblingType,
      platformName: _platform,
      notes: _notes.text,
    );
    final repo = ref.read(trackerRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.update(widget.existing!.id, input);
      } else {
        await repo.add(input);
      }
      if (mounted) context.pop();
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
        title: const Text('Delete this entry?'),
        content: const Text('It will be removed from this phone and from your totals.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(trackerRepositoryProvider).delete(widget.existing!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platforms = ref.watch(platformNamesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit entry' : 'Add an entry'),
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
              Text('What happened?', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final type in GamblingEntryType.values)
                    ChoiceChip(label: Text(type.label), selected: _type == type, onSelected: (_) => setState(() => _type = type)),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(_type.description, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount', prefixText: 'R '),
                validator: (text) => parseRandsToCents(text ?? '') == null ? 'Enter an amount, like 250 or 250.50' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Date'),
                subtitle: Text(DateFormat('EEEE d MMMM y').format(_date)),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _pickDate,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<GamblingType>(
                isExpanded: true,
                initialValue: _gamblingType,
                decoration: const InputDecoration(labelText: 'Type of gambling'),
                items: [for (final t in GamblingType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                onChanged: (t) => setState(() => _gamblingType = t ?? _gamblingType),
              ),
              const SizedBox(height: AppSpacing.md),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _platform),
                optionsBuilder: (value) {
                  final query = value.text.trim().toLowerCase();
                  return query.isEmpty ? platforms : platforms.where((p) => p.toLowerCase().contains(query));
                },
                onSelected: (name) => _platform = name,
                fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Where (optional)', counterText: ''),
                  onChanged: (text) => _platform = text,
                  onFieldSubmitted: (_) => onSubmitted(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notes,
                maxLength: 1000,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'What was going on? Only you can see this.'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Tip: log either money moved (deposits and withdrawals) or results (losses and wins). '
                'Logging both for the same money counts it twice.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'Save changes' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
