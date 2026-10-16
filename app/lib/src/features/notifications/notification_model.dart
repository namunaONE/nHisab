class NotificationRow {
  final String id;
  final String? loanId;
  final String? partyName;
  final String alertType;
  final String channel; // 'email' | 'sms' | 'in_app'
  final String status; // 'pending' | 'sent' | 'failed'
  final DateTime? scheduledAt;
  final DateTime? sentAt;
  final DateTime createdAt;

  NotificationRow({
    required this.id,
    this.loanId,
    this.partyName,
    required this.alertType,
    required this.channel,
    required this.status,
    this.scheduledAt,
    this.sentAt,
    required this.createdAt,
  });

  /// Unread = still pending delivery/read.
  bool get isUnread => status == 'pending';

  factory NotificationRow.fromMap(Map<String, dynamic> r) {
    DateTime? dt(dynamic v) =>
        v == null ? null : DateTime.parse(v as String);
    final loan = r['loans'] as Map?;
    final party = loan?['parties'] as Map?;
    return NotificationRow(
      id: (r['id'] ?? '').toString(),
      loanId: r['loan_id']?.toString(),
      partyName: party?['name']?.toString(),
      alertType: (r['alert_type'] ?? '').toString(),
      channel: (r['channel'] ?? '').toString(),
      status: (r['status'] ?? '').toString(),
      scheduledAt: dt(r['scheduled_at']),
      sentAt: dt(r['sent_at']),
      createdAt: DateTime.parse(r['created_at'] as String),
    );
  }
}
