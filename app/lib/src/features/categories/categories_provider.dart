import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/cache/cache_service.dart';
import 'category_model.dart';

/// Cached read-through: serves Hive rows when offline. Returns [] when budget
/// tables are not yet migrated.
final categoriesProvider = FutureProvider<List<CategoryRow>>((ref) async {
  try {
    final result = await CacheService.fetchOrCache(
      key: 'categories:all',
      fetch: () async => await Supabase.instance.client
          .from('categories')
          .select('id, kind, name, icon')
          .filter('deleted_at', 'is', null)
          .order('kind')
          .order('name') as List,
    );
    return CacheService.parseAll(result.rows, (r) {
      return CategoryRow(
        id: (r['id'] ?? '').toString(),
        kind: (r['kind'] ?? '').toString(),
        name: (r['name'] ?? '').toString(),
        icon: r['icon'] as String?,
      );
    });
  } catch (_) {
    return <CategoryRow>[];
  }
});
