import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhisab/src/features/notifications/notification_model.dart';
import 'package:nhisab/src/features/notifications/notifications_button.dart';
import 'package:nhisab/src/features/notifications/notifications_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _initSupabase() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  try {
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-anon-key',
    );
  } catch (_) {
    // Already initialized across test files in the same run.
  }
}

NotificationRow _row(String id, String status) => NotificationRow(
      id: id,
      alertType: 'overdue',
      channel: 'in_app',
      status: status,
      createdAt: DateTime(2026, 10, 15, 8),
    );

void main() {
  setUpAll(_initSupabase);

  testWidgets('Bell shows unread badge count', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unreadNotificationsProvider.overrideWith(
              (ref) async => 3),
          notificationsProvider.overrideWith((ref) async => <NotificationRow>[]),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotificationsButton()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('Bell with zero unread shows no badge', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unreadNotificationsProvider.overrideWith((ref) async => 0),
          notificationsProvider.overrideWith((ref) async => <NotificationRow>[]),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotificationsButton()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(NotificationsButton), findsOneWidget);
    // Badge container only renders when unread > 0.
    expect(find.text('0'), findsNothing);
  });

  testWidgets('Tapping bell opens tray with rows', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unreadNotificationsProvider.overrideWith((ref) async => 1),
          notificationsProvider.overrideWith(
              (ref) async => [_row('n1', 'pending')]),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotificationsButton()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(NotificationsButton));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Payment overdue'), findsOneWidget);
  });
}
