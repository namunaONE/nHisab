import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/cache/cache_service.dart';

class Party {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? idNumber;
  final String? idType;
  final bool idVerified;
  final String riskRating;
  Party({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.idNumber,
    this.idType,
    this.idVerified = false,
    this.riskRating = 'low',
  });
}

final partiesProvider = FutureProvider<List<Party>>((ref) async {
  final result = await CacheService.fetchOrCache(
    key: 'parties:all',
    fetch: () async => await Supabase.instance.client
        .from('parties_with_pii')
        .select('id, name, phone, address, id_number, id_type, id_verified, risk_rating')
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
      idNumber: m['id_number'] as String?,
      idType: m['id_type'] as String?,
      idVerified: (m['id_verified'] as bool?) ?? false,
      riskRating: (m['risk_rating'] ?? 'low').toString(),
    );
  });
});
