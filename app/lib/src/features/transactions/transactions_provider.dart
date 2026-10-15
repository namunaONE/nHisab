import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'transaction_model.dart';

/// Returns [] when budget tables are not yet migrated (keeps Pages green).
final transactionsProvider = FutureProvider<List<TxnRow>>((ref) async {
  try {
    final res = await Supabase.instance.client
        .from('transactions')
        .select(
            'id, kind, amount, txn_date, accounts(name), categories(name)')
        .filter('deleted_at', 'is', null)
        .order('txn_date', ascending: false)
        .limit(200);
    return (res as List).map((r) {
      final acc = (r['accounts'] as Map?)?['name'] ?? '-';
      final cat = (r['categories'] as Map?)?['name'];
      return TxnRow(
        id: (r['id'] ?? '').toString(),
        accountName: acc.toString(),
        categoryName: cat?.toString(),
        kind: (r['kind'] ?? '').toString(),
        amount: ((r['amount'] as num?) ?? 0).toDouble(),
        date: DateTime.parse(r['txn_date'] as String),
      );
    }).toList();
  } catch (_) {
    return <TxnRow>[];
  }
});
