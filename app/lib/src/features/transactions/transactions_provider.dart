import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/cache/cache_service.dart';
import 'transaction_model.dart';

/// Cached read-through: serves Hive rows when offline. Returns [] when budget
/// tables are not yet migrated (keeps Pages green).
final transactionsProvider = FutureProvider<List<TxnRow>>((ref) async {
  try {
    final result = await CacheService.fetchOrCache(
      key: 'transactions:200',
      fetch: () async => await Supabase.instance.client
          .from('transactions')
          .select(
              'id, kind, amount, txn_date, accounts(name), categories(name)')
          .filter('deleted_at', 'is', null)
          .order('txn_date', ascending: false)
          .limit(200) as List,
    );
    return CacheService.parseAll(result.rows, (r) {
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
    });
  } catch (_) {
    return <TxnRow>[];
  }
});
