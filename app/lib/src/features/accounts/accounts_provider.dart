import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/budget/budget_calculator.dart';
import '../../core/cache/cache_service.dart';
import 'account_model.dart';

/// Cached read-through: serves Hive rows when offline. Returns [] when budget
/// tables are not yet migrated (keeps Pages green).
final accountsProvider = FutureProvider<List<AccountRow>>((ref) async {
  try {
    final client = Supabase.instance.client;
    List res;
    List txns;
    try {
      res = await client
          .from('accounts')
          .select('id, name, type, opening_balance')
          .filter('deleted_at', 'is', null)
          .order('name') as List;
      txns = await client
          .from('transactions')
          .select('account_id, kind, amount')
          .filter('deleted_at', 'is', null) as List;
      await CacheService.writeMap(
          'accounts:all', {'accounts': res, 'txns': txns});
    } catch (_) {
      final cached = CacheService.readMap('accounts:all');
      if (cached == null) return <AccountRow>[];
      res = (cached['accounts'] as List?) ?? [];
      txns = (cached['txns'] as List?) ?? [];
    }
    final byAccount = <String, List<({String kind, double amount})>>{};
    for (final t in txns) {
      if (t is! Map) continue;
      final aid = (t['account_id'] ?? '').toString();
      byAccount.putIfAbsent(aid, () => []).add((
        kind: (t['kind'] ?? '').toString(),
        amount: ((t['amount'] as num?) ?? 0).toDouble(),
      ));
    }
    return CacheService.parseAll(res, (r) {
      final opening = ((r['opening_balance'] as num?) ?? 0).toDouble();
      final row = AccountRow(
        id: (r['id'] ?? '').toString(),
        name: (r['name'] ?? '-').toString(),
        type: (r['type'] ?? 'cash').toString(),
        openingBalance: opening,
      );
      row.computedBalance = BudgetCalculator.accountBalance(
        opening: opening,
        txns: byAccount[row.id] ?? const [],
      );
      return row;
    });
  } catch (_) {
    return <AccountRow>[];
  }
});
