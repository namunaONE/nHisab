import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Party {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  Party({required this.id, required this.name, this.phone, this.address});
}

final partiesProvider = FutureProvider<List<Party>>((ref) async {
  final res = await Supabase.instance.client.from('parties').select('id, name, phone, address').filter('deleted_at', 'is', null).order('name');
  return (res as List).map((r) => Party(
    id: r['id'] as String,
    name: (r['name'] ?? '').toString(),
    phone: r['phone'] as String?,
    address: r['address'] as String?,
  )).toList();
});
