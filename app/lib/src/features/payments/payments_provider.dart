import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/cache/cache_service.dart';

class PaymentRow {
  final String id;
  final String loanId;
  final String partyName;
  final DateTime date;
  final double total;
  final String? method;
  PaymentRow({required this.id, required this.loanId, required this.partyName, required this.date, required this.total, this.method});
}

final paymentsProvider = FutureProvider<List<PaymentRow>>((ref) async {
  final result = await CacheService.fetchOrCache(
    key: 'payments:200',
    fetch: () async => await Supabase.instance.client
        .from('payments')
        .select('id, loan_id, payment_date, total_amount, payment_method, loans(parties(name))')
        .filter('deleted_at', 'is', null)
        .order('payment_date', ascending: false)
        .limit(200) as List,
  );
  return CacheService.parseAll(result.rows, (r) {
    final loan = r['loans'] as Map?;
    final party = (loan?['parties'] as Map?)?['name'] ?? '-';
    return PaymentRow(
      id: (r['id'] ?? '').toString(),
      loanId: (r['loan_id'] ?? '').toString(),
      partyName: party.toString(),
      date: DateTime.parse(r['payment_date'] as String),
      total: ((r['total_amount'] as num?) ?? 0).toDouble(),
      method: r['payment_method'] as String?,
    );
  });
});
