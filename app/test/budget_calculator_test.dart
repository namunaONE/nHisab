import 'package:flutter_test/flutter_test.dart';
import 'package:nhisab/src/core/budget/budget_calculator.dart';

void main() {
  test('Account balance signs income/expense, ignores transfer', () {
    final b = BudgetCalculator.accountBalance(
      opening: 10000,
      txns: [
        (kind: 'income', amount: 5000),
        (kind: 'expense', amount: 2000),
        (kind: 'transfer', amount: 9999),
      ],
    );
    expect(b, 13000.0);
  });

  test('Budget remaining clamps, overspend flags', () {
    expect(BudgetCalculator.budgetSpent(expenseAmounts: [2000, 1500]), 3500.0);
    expect(BudgetCalculator.budgetRemaining(limit: 5000, spent: 3500), 1500.0);
    expect(BudgetCalculator.budgetRemaining(limit: 3000, spent: 3500), 0.0);
    expect(BudgetCalculator.isOverspent(limit: 3000, spent: 3500), isTrue);
    expect(BudgetCalculator.isOverspent(limit: 5000, spent: 3500), isFalse);
  });

  test('Nepal FY buckets Jul-Jun', () {
    expect(BudgetCalculator.fyStartYear(DateTime(2026, 10, 15)), 2026);
    expect(BudgetCalculator.fyMonth(DateTime(2026, 7, 16)), 1);
    expect(BudgetCalculator.fyMonth(DateTime(2026, 10, 15)), 4);
    expect(BudgetCalculator.fyMonth(DateTime(2026, 6, 15)), 12);
    expect(BudgetCalculator.fyLabel(DateTime(2026, 10, 15)), 'FY 2026/27');
  });

  test('Net worth adds accounts, nets loans', () {
    final w = BudgetCalculator.netWorth(
      accountBalances: [50000, 20000],
      receivableOutstanding: 9960000,
      payableOutstanding: 85713900,
    );
    expect(w, 50000 + 20000 + 9960000 - 85713900);
  });
}
