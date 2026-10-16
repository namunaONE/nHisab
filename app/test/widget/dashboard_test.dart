import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhisab/src/features/accounts/account_model.dart';
import 'package:nhisab/src/features/accounts/accounts_provider.dart';
import 'package:nhisab/src/features/budgets/budget_model.dart';
import 'package:nhisab/src/features/budgets/budgets_provider.dart';
import 'package:nhisab/src/features/dashboard/dashboard_page.dart';
import 'package:nhisab/src/features/loans/loan_model.dart';
import 'package:nhisab/src/features/loans/loans_provider.dart';
import 'package:nhisab/src/features/transactions/transaction_model.dart';
import 'package:nhisab/src/features/transactions/transactions_provider.dart';
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

Widget _harness() {
  return ProviderScope(
    overrides: [
      accountsProvider.overrideWith((ref) async => <AccountRow>[]),
      transactionsProvider.overrideWith((ref) async => <TxnRow>[]),
      budgetsProvider.overrideWith((ref) async => <BudgetRow>[]),
      loansProvider.overrideWith((ref) async => <LoanRow>[]),
    ],
    child: const MaterialApp(home: DashboardPage()),
  );
}

void main() {
  setUpAll(_initSupabase);

  testWidgets('Dashboard renders all panels on empty data', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Net cash in wallets'), findsOneWidget);
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('No budgets yet'), findsOneWidget);
    // Loan strip is below the fold in the ListView — scroll to it.
    await tester.scrollUntilVisible(
      find.textContaining('active loans'),
      200,
    );
    expect(find.textContaining('active loans'), findsOneWidget);
  });

  testWidgets('Dashboard shows wallet total from provider', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsProvider.overrideWith((ref) async => [
                AccountRow(
                  id: 'a1',
                  name: 'Cash',
                  type: 'cash',
                  openingBalance: 50000,
                  computedBalance: 65000,
                ),
              ]),
          transactionsProvider.overrideWith((ref) async => <TxnRow>[]),
          budgetsProvider.overrideWith((ref) async => <BudgetRow>[]),
          loansProvider.overrideWith((ref) async => <LoanRow>[]),
        ],
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('65,000.00'), findsOneWidget);
    expect(find.textContaining('1 wallets'), findsOneWidget);
  });
}
