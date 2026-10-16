import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhisab/src/core/widgets/empty_state.dart';
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

void main() {
  setUpAll(_initSupabase);

  testWidgets('EmptyState renders title, subtitle and fires CTA',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.wallet,
            title: 'No wallets yet',
            subtitle: 'Add one to start.',
            ctaLabel: 'Add wallet',
            onCta: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('No wallets yet'), findsOneWidget);
    expect(find.text('Add one to start.'), findsOneWidget);
    await tester.tap(find.text('Add wallet'));
    expect(tapped, isTrue);
  });

  testWidgets('EmptyState without CTA shows no button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(icon: Icons.history, title: 'Nothing here'),
        ),
      ),
    );

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('ErrorState renders message and fires retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorState(
            message: 'boom',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
