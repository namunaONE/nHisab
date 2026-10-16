import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhisab/src/features/home/ledger_page.dart';
import 'package:nhisab/src/features/loans/loan_model.dart';
import 'package:nhisab/src/features/loans/loans_provider.dart';
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

Widget _harness(List<LoanRow> loans) {
  return ProviderScope(
    overrides: [
      loansProvider.overrideWith((ref) async => loans),
      todayProvider.overrideWith((ref) => DateTime(2026, 10, 15)),
      directionFilterProvider.overrideWith((ref) => 'receivable'),
    ],
    child: const MaterialApp(home: LedgerPage()),
  );
}

void main() {
  setUpAll(_initSupabase);

  testWidgets('Ledger shows empty state when no loans', (tester) async {
    await tester.pumpWidget(_harness([]));
    await tester.pumpAndSettle();

    expect(find.text('No loans yet'), findsOneWidget);
  });

  testWidgets('Ledger desktop shows table row for a loan', (tester) async {
    await tester.pumpWidget(_harness([
      LoanRow(
        id: 'l1',
        partyName: 'Madhu (Japan)',
        principal: 1500000,
        rate: 0.18,
        rateType: 'annual',
        dayBase: 360,
        startDate: DateTime(2026, 6, 19),
        direction: 'receivable',
        paid: 0,
      ),
    ]));
    await tester.pumpAndSettle();

    // Desktop layout (>=600px default surface): DataTable headers + row.
    expect(find.text('Madhu (Japan)'), findsOneWidget);
    expect(find.text('1,588,500.00'),
        findsWidgets); // total 1500000+88500, row + footer
  });

  testWidgets('Ledger mobile shows card for a loan', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_harness([
      LoanRow(
        id: 'l1',
        partyName: 'Madhu (Japan)',
        principal: 1500000,
        rate: 0.18,
        rateType: 'annual',
        dayBase: 360,
        startDate: DateTime(2026, 6, 19),
        direction: 'receivable',
        paid: 0,
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Madhu (Japan)'), findsOneWidget);
    expect(find.text('1,588,500.00'), findsOneWidget);
  });
}
