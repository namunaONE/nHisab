class AuditRow {
  final String id;
  final String tableName;
  final String? rowId;
  final String action;
  final DateTime createdAt;

  AuditRow({
    required this.id,
    required this.tableName,
    this.rowId,
    required this.action,
    required this.createdAt,
  });

  factory AuditRow.fromMap(Map<String, dynamic> r) {
    return AuditRow(
      id: (r['id'] ?? '').toString(),
      tableName: (r['table_name'] ?? '').toString(),
      rowId: r['row_id']?.toString(),
      action: (r['action'] ?? '').toString(),
      createdAt: DateTime.parse(r['created_at'] as String),
    );
  }
}
