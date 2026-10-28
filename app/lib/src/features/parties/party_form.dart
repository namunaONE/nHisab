import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_service.dart';
import 'parties_provider.dart';

class PartyFormDialog extends ConsumerStatefulWidget {
  final Party? party;
  const PartyFormDialog({super.key, this.party});

  @override
  ConsumerState<PartyFormDialog> createState() => _PartyFormDialogState();
}

class _PartyFormDialogState extends ConsumerState<PartyFormDialog> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final idNo = TextEditingController();
  String? idType;
  String riskRating = 'low';
  bool idVerified = false;
  bool busy = false;
  String? error;

  bool get isEdit => widget.party != null;

  @override
  void initState() {
    super.initState();
    final p = widget.party;
    if (p != null) {
      name.text = p.name;
      phone.text = p.phone ?? '';
      address.text = p.address ?? '';
      idNo.text = p.idNumber ?? '';
      idType = p.idType;
      riskRating = p.riskRating;
      idVerified = p.idVerified;
    }
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Name required');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final data = {
        'name': name.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'address': address.text.trim().isEmpty ? null : address.text.trim(),
        'id_number': idNo.text.trim().isEmpty ? null : idNo.text.trim(),
        'id_type': idType,
        'risk_rating': riskRating,
        'id_verified': idVerified,
      };
      if (isEdit) {
        final p = widget.party!;
        final oldData = {
          'name': p.name,
          'phone': p.phone,
          'address': p.address,
          'id_number': p.idNumber,
          'id_type': p.idType,
          'risk_rating': p.riskRating,
          'id_verified': p.idVerified,
        };
        await Supabase.instance.client
            .from('parties')
            .update(data)
            .eq('id', p.id);
        await AuditLog.write(
            table: 'parties',
            rowId: p.id,
            action: 'update',
            oldData: oldData,
            newData: data);
      } else {
        final row = await Supabase.instance.client
            .from('parties')
            .insert(data)
            .select('id')
            .single();
        await AuditLog.write(
            table: 'parties',
            rowId: (row['id'] ?? '').toString(),
            action: 'insert',
            newData: data);
      }
      ref.invalidate(partiesProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    address.dispose();
    idNo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEdit ? 'Edit Party' : 'Add Party'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Party Name * e.g. Madhu (Japan)')),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
            TextField(controller: idNo, decoration: const InputDecoration(labelText: 'Citizenship / ID No')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: idType,
              decoration: const InputDecoration(labelText: 'ID Type'),
              items: const [
                DropdownMenuItem(value: 'citizenship', child: Text('Citizenship')),
                DropdownMenuItem(value: 'passport', child: Text('Passport')),
                DropdownMenuItem(value: 'nid', child: Text('NID')),
                DropdownMenuItem(value: 'pan', child: Text('PAN')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => idType = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: riskRating,
              decoration: const InputDecoration(labelText: 'Risk rating'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('High')),
              ],
              onChanged: (v) => setState(() => riskRating = v ?? 'low'),
            ),
            CheckboxListTile(
              title: const Text('ID verified'),
              value: idVerified,
              onChanged: (v) => setState(() => idVerified = v ?? false),
            ),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Saving...' : (isEdit ? 'Update' : 'Save'))),
      ],
    );
  }
}
