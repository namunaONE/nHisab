import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/cache/cache_service.dart';

class Party {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  Party({required this.id, required this.name, this.phone, this.address});
}

final partiesProvider = FutureProvider<List<Party>>((ref) async {
  final result = await CacheService.fetchOrCache(
    key: 'parties:all',
    fetch: () async => await Supabase.instance.client
        .from('parties')
        .select('id, name, phone, address')
        .filter('deleted_at', 'is', null)
        .order('name') as List,
  );
  return CacheService.parseAll(result.rows, (r) {
    final m = r;
    return Party(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      phone: m['phone'] as String?,
      address: m['address'] as String?,
    );
  });
});
