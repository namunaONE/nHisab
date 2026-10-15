import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'category_model.dart';

/// Returns [] when budget tables are not yet migrated.
final categoriesProvider = FutureProvider<List<CategoryRow>>((ref) async {
  try {
    final res = await Supabase.instance.client
        .from('categories')
        .select('id, kind, name, icon')
        .filter('deleted_at', 'is', null)
        .order('kind')
        .order('name');
    return (res as List)
        .map((r) => CategoryRow(
              id: (r['id'] ?? '').toString(),
              kind: (r['kind'] ?? '').toString(),
              name: (r['name'] ?? '').toString(),
              icon: r['icon'] as String?,
            ))
        .toList();
  } catch (_) {
    return <CategoryRow>[];
  }
});
