import 'package:flutter_test/flutter_test.dart';
import 'package:nhisab/src/features/notifications/notification_model.dart';

void main() {
  test('fromMap parses nested loan->party join', () {
    final n = NotificationRow.fromMap({
      'id': 'n1',
      'loan_id': 'l1',
      'alert_type': 'overdue',
      'channel': 'in_app',
      'status': 'pending',
      'scheduled_at': null,
      'sent_at': null,
      'created_at': '2026-10-15T08:00:00Z',
      'loans': {
        'parties': {'name': 'Madhu (Japan)'}
      },
    });
    expect(n.id, 'n1');
    expect(n.partyName, 'Madhu (Japan)');
    expect(n.isUnread, isTrue);
  });

  test('Sent rows are read', () {
    final n = NotificationRow.fromMap({
      'id': 'n2',
      'loan_id': null,
      'alert_type': 'due_soon',
      'channel': 'email',
      'status': 'sent',
      'scheduled_at': null,
      'sent_at': '2026-10-15T08:05:00Z',
      'created_at': '2026-10-15T08:00:00Z',
      'loans': null,
    });
    expect(n.isUnread, isFalse);
    expect(n.partyName, isNull);
  });
}
