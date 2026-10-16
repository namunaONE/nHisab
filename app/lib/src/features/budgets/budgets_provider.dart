import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/budget/budget_calculator.dart';
import '../../core/cache/cache_service.dart';
import 'budget_model.dart';

/// Spent rollup: sums expense txns whose txn_date maps to the budget FY month.
/// Cached read-through: serves Hive rows when offline.
final budgetsProvider = FutureProvider<List<BudgetRow>>((ref) async {
  try {
    final client = Supabase.instance.client;
    List res;
    List txns;
    try {
      res = await client
          .from('budgets')
          .select(
              'id, category_id, fy_year, fy_month, limit_amount, categories(name)')
          .filter('deleted_at', 'is', null)
          .order('fy_year')
          .order('fy_month') as List;
      txns = await client
          .from('transactions')
          .select('category_id, kind, amount, txn_date')
          .filter('deleted_at', 'is', null)
          .eq('kind', 'expense') as List;
      await CacheService.writeMap(
          'budgets:all', {'budgets': res, 'txns': txns});
    } catch (_) {
      final cached = CacheService.readMap('budgets:all');
      if (cached == null) return <BudgetRow>[];
      res = (cached['budgets'] as List?) ?? [];
      txns = (cached['txns'] as List?) ?? [];
    }
    final spentByKey = <String, double>{};
    for (final t in txns) {
      if (t is! Map) continue;
      final cid = (t['category_id'] ?? '').toString();
      if (cid.isEmpty) continue;
      final d = DateTime.parse(t['txn_date'] as String);
      final key =
          '$cid|${BudgetCalculator.fyStartYear(d)}|${BudgetCalculator.fyMonth(d)}';
      spentByKey[key] = (spentByKey[key] ?? 0) +
          (((t['amount'] as num?) ?? 0).toDouble());
    }
    return CacheService.parseAll(res, (r) {
      final cat = (r['categories'] as Map?)?['name'] ?? '-';
      final cid = (r['category_id'] ?? '').toString();
      final fy = ((r['fy_year'] as num?) ?? 0).toInt();
      final fm = ((r['fy_month'] as num?) ?? 0).toInt();
      return BudgetRow(
        id: (r['id'] ?? '').toString(),
        categoryName: cat.toString(),
        fyYear: fy,
        fyMonth: fm,
        limit: ((r['limit_amount'] as num?) ?? 0).toDouble(),
        spent: BudgetCalculator.round2(spentByKey['$cid|$fy|$fm'] ?? 0),
      );
    });
  } catch (_) {
    return <BudgetRow>[];
  }
});
