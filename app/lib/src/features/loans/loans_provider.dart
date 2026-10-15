import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'loan_model.dart';

final todayProvider = StateProvider<DateTime>((ref) => DateTime.now());
final directionFilterProvider = StateProvider<String>((ref) => 'receivable');

final loansProvider = FutureProvider<List<LoanRow>>((ref) async {
  final direction = ref.watch(directionFilterProvider);
  final client = Supabase.instance.client;
  final res = await client
      .from('loans')
      .select('id, principal_amount, rate, rate_type, day_base, start_date, direction, parties(name)')
      .eq('direction', direction)
      .eq('status', 'active')
      .filter('deleted_at', 'is', null)
      .order('start_date');
  final pays = await client.from('payments').select('loan_id, total_amount').filter('deleted_at', 'is', null);
  final paidByLoan = <String, double>{};
  for (final p in (pays as List)) {
    final lid = p['loan_id'] as String;
    paidByLoan[lid] = (paidByLoan[lid] ?? 0) + ((p['total_amount'] as num).toDouble());
  }
  return (res as List).map((r) {
    final party = (r['parties'] as Map?)?['name'] ?? '-';
    return LoanRow(
      id: r['id'] as String,
      partyName: party.toString(),
      principal: (r['principal_amount'] as num).toDouble(),
      rate: (r['rate'] as num).toDouble(),
      rateType: r['rate_type'] as String,
      dayBase: (r['day_base'] as num).toInt(),
      startDate: DateTime.parse(r['start_date'] as String),
      direction: r['direction'] as String,
      paid: paidByLoan[r['id']] ?? 0,
    );
  }).toList();
});
