import 'package:flutter_test/flutter_test.dart';
import 'package:nhisab/src/core/audit/audit_service.dart';

void main() {
  test('Payload keeps table/row/action/actor shape', () {
    final p = AuditLog.payload(
      table: 'loans',
      rowId: 'abc-123',
      action: 'insert',
      newData: {'principal_amount': 1500000},
      actor: 'user-1',
    );
    expect(p['table_name'], 'loans');
    expect(p['row_id'], 'abc-123');
    expect(p['action'], 'insert');
    expect(p['actor'], 'user-1');
    expect((p['new_data'] as Map)['principal_amount'], 1500000);
  });

  test('Sanitizer drops nulls and secret-like keys', () {
    final p = AuditLog.payload(
      table: 'parties',
      action: 'insert',
      newData: {
        'name': 'Madhu',
        'phone': null,
        'password': 'hunter2',
        'api_token': 'xyz',
      },
    );
    final data = p['new_data'] as Map;
    expect(data['name'], 'Madhu');
    expect(data.containsKey('phone'), isFalse);
    expect(data.containsKey('password'), isFalse);
    expect(data.containsKey('api_token'), isFalse);
  });

  test('Null newData stays null', () {
    final p = AuditLog.payload(table: 'loans', action: 'archive', rowId: 'x');
    expect(p['new_data'], isNull);
    expect(p['old_data'], isNull);
  });
}
