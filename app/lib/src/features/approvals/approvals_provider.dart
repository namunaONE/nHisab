import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApprovalRow {
  final String id;
  final String entityType;
  final String action;
  final String status;
  final String? requestedBy;
  final DateTime requestedAt;
  final Map<String, dynamic> payload;
  ApprovalRow({
    required this.id,
    required this.entityType,
    required this.action,
    required this.status,
    this.requestedBy,
    required this.requestedAt,
    required this.payload,
  });
  factory ApprovalRow.fromMap(Map<String, dynamic> m) => ApprovalRow(
        id: (m['id'] ?? '').toString(),
        entityType: (m['entity_type'] ?? '').toString(),
        action: (m['action'] ?? '').toString(),
        status: (m['status'] ?? 'pending').toString(),
        requestedBy: m['requested_by']?.toString(),
        requestedAt: DateTime.parse(m['requested_at'] as String),
        payload: Map<String, dynamic>.from(m['payload'] as Map? ?? {}),
      );
}

final approvalsProvider = FutureProvider<List<ApprovalRow>>((ref) async {
  final client = Supabase.instance.client;
  final res = await client
      .from('approval_requests')
      .select('*')
      .order('requested_at', ascending: false) as List;
  return res.map((r) => ApprovalRow.fromMap(Map<String, dynamic>.from(r))).toList();
});