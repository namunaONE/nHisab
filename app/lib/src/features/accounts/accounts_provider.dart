import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/budget/budget_calculator.dart';
import 'account_model.dart';

/// Returns [] when budget tables are not yet migrated (keeps Pages green).
final accountsProvider = FutureProvider<List<AccountRow>>((ref) async {
  try {
    final client = Supabase.instance.client;
    final res = await client
        .from('accounts')
        .select('id, name, type, opening_balance')
        .filter('deleted_at', 'is', null)
        .order('name');
    final txns = await client
        .from('transactions')
        .select('account_id, kind, amount')
        .filter('deleted_at', 'is', null);
    final byAccount = <String, List<({String kind, double amount})>>{};
    for (final t in (txns as List)) {
      final aid = (t['account_id'] ?? '').toString();
      byAccount.putIfAbsent(aid, () => []).add((
        kind: (t['kind'] ?? '').toString(),
        amount: ((t['amount'] as num?) ?? 0).toDouble(),
      ));
    }
    return (res as List).map((r) {
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
    }).toList();
  } catch (_) {
    return <AccountRow>[];
  }
});
