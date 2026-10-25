import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/cache/cache_service.dart';
import 'loan_model.dart';

final todayProvider = StateProvider<DateTime>((ref) => DateTime.now());
final directionFilterProvider = StateProvider<String>((ref) => 'receivable');

final loansProvider = FutureProvider<List<LoanRow>>((ref) async {
  final direction = ref.watch(directionFilterProvider);
  final client = Supabase.instance.client;
  final cacheKey = 'loans:$direction';

  List loansRes;
  List paysRes;
  try {
    // `*` keeps the client compatible during the expand phase: the new
    // accrual_end_date column is optional until the migration is applied.
    loansRes = await client
        .from('loans')
        .select('*, parties(name)')
        .eq('direction', direction)
        .eq('status', 'active')
        .filter('deleted_at', 'is', null)
        .order('start_date') as List;
    paysRes = await client
        .from('payments')
        .select(
            'loan_id, total_amount, interest_amount, principal_amount')
        .filter('deleted_at', 'is', null) as List;
    await CacheService.writeMap(
        cacheKey, {'loans': loansRes, 'pays': paysRes});
  } catch (_) {
    final cached = CacheService.readMap(cacheKey);
    if (cached == null) rethrow;
    loansRes = (cached['loans'] as List?) ?? [];
    paysRes = (cached['pays'] as List?) ?? [];
  }

  final paidByLoan = <String, double>{};
  final interestPaidByLoan = <String, double>{};
  final principalPaidByLoan = <String, double>{};
  for (final p in paysRes) {
    if (p is! Map) continue;
    final lid = p['loan_id']?.toString() ?? '';
    paidByLoan[lid] =
        (paidByLoan[lid] ?? 0) + (((p['total_amount'] as num?) ?? 0).toDouble());
    interestPaidByLoan[lid] = (interestPaidByLoan[lid] ?? 0) +
        (((p['interest_amount'] as num?) ?? 0).toDouble());
    principalPaidByLoan[lid] = (principalPaidByLoan[lid] ?? 0) +
        (((p['principal_amount'] as num?) ?? 0).toDouble());
  }
  return CacheService.parseAll(loansRes, (r) {
    final party = (r['parties'] as Map?)?['name'] ?? '-';
    final id = (r['id'] ?? '').toString();
    return LoanRow(
      id: id,
      partyName: party.toString(),
      principal: ((r['principal_amount'] as num?) ?? 0).toDouble(),
      rate: ((r['rate'] as num?) ?? 0).toDouble(),
      rateType: (r['rate_type'] ?? 'annual').toString(),
      dayBase: ((r['day_base'] as num?) ?? 360).toInt(),
      startDate: DateTime.parse(r['start_date'] as String),
      direction: (r['direction'] ?? '').toString(),
      paid: paidByLoan[id] ?? 0,
      interestPaid: interestPaidByLoan[id] ?? 0,
      principalPaid: principalPaidByLoan[id] ?? 0,
    );
  });
});
