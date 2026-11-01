import 'package:flutter/material.dart';

import '../../features/tracker/domain/money.dart';
import '../theme/app_theme.dart';

/// Asks for an amount in rands. Returns cents, or null if cancelled.
Future<int?> showAmountDialog(
  BuildContext context, {
  required String title,
  String? message,
  int? initialCents,
  int? maxCents,
  String saveLabel = 'Add',
}) =>
    showDialog<int>(
      context: context,
      builder: (_) => _AmountDialog(
        title: title,
        message: message,
        initialCents: initialCents,
        maxCents: maxCents,
        saveLabel: saveLabel,
      ),
    );

/// Owns its text controller, so the controller lives exactly as long as the dialog (including
/// its closing animation).
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.title, required this.saveLabel, this.message, this.initialCents, this.maxCents});

  final String title;
  final String? message;
  final int? initialCents;
  final int? maxCents;
  final String saveLabel;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final cents = widget.initialCents;
    _controller = TextEditingController(text: cents == null ? '' : (cents / 100).toStringAsFixed(cents % 100 == 0 ? 0 : 2));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) Navigator.pop(context, parseRandsToCents(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.maxCents;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: AppSpacing.md)],
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: 'R '),
              onFieldSubmitted: (_) => _submit(),
              validator: (text) {
                final cents = parseRandsToCents(text ?? '');
                if (cents == null) return 'Enter an amount, like 250 or 250.50';
                if (max != null && cents > max) return 'At most ${formatRands(max)}';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: Text(widget.saveLabel)),
      ],
    );
  }
}
