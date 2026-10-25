import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'loan_model.dart';

/// Closes a loan through the server RPC.
///
/// Full settlement is the default. A write-off must be ticked explicitly and
/// needs a reason, matching close_loan's server-side guard.
class CloseLoanDialog extends ConsumerStatefulWidget {
  final LoanRow loan;
  const CloseLoanDialog({super.key, required this.loan});

  @override
  ConsumerState<CloseLoanDialog> createState() => _CloseLoanDialogState();
}

class _CloseLoanDialogState extends ConsumerState<CloseLoanDialog> {
  bool writeOff = false;
  bool busy = false;
  String? error;
  final reason = TextEditingController();

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  bool _isMissingFunction(PostgrestException e) {
    return e.code == 'PGRST202' ||
        e.code == '42883' ||
        e.message.toLowerCase().contains('could not find the function');
  }

  Future<void> _submit() async {
    final trimmed = reason.text.trim();
    if (writeOff && trimmed.isEmpty) {
      setState(() => error = 'A write-off reason is required.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Supabase.instance.client.rpc('close_loan', params: {
        'p_loan_id': widget.loan.id,
        'p_write_off': writeOff,
        'p_reason': writeOff ? trimmed : null,
      });
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => error = _isMissingFunction(e)
            ? 'Close-loan is not deployed yet. Apply migration 20261025121000 and retry.'
            : e.message);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Close ${widget.loan.partyName}\'s loan?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Accrual stops on the Nepal date the server confirms. '
              'A loan with any unpaid principal or interest cannot be closed '
              'unless the balance is explicitly written off.',
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: writeOff,
              contentPadding: EdgeInsets.zero,
              title: const Text('Write off the remaining balance'),
              subtitle: const Text(
                  'Recorded in the audit trail and shown on the party statement.'),
              onChanged: busy
                  ? null
                  : (v) => setState(() => writeOff = v ?? false),
            ),
            if (writeOff)
              TextField(
                controller: reason,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Write-off reason *',
                  hintText: 'e.g. borrower absconded, board-approved settlement',
                ),
              ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: Text(busy ? 'Closing...' : 'Close loan'),
        ),
      ],
    );
  }
}
