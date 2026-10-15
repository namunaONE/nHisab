// Budget tracker pure math. Wallets-first, no Flutter deps.
// Locked 2026-10-15: every money event hits one account, no double-count.
// Sums are Decimal-exact via [Money]; public API unchanged.
import '../money/money.dart';

class BudgetCalculator {
  static double round2(double v) => (v * 100).round() / 100;

  /// Signed sum: income +, expense -. Transfers excluded by caller.
  static double signedSum({required String kind, required double amount}) {
    if (kind == 'income') return amount;
    if (kind == 'expense') return -amount;
    return 0;
  }

  static double accountBalance({
    required double opening,
    required List<({String kind, double amount})> txns,
  }) {
    final signed = <double>[opening];
    for (final t in txns) {
      signed.add(signedSum(kind: t.kind, amount: t.amount));
    }
    return Money.sum2(signed);
  }

  static double budgetSpent({required List<double> expenseAmounts}) {
    return Money.sum2(expenseAmounts);
  }

  static double budgetRemaining({required double limit, required double spent}) {
    return round2((limit - spent).clamp(0, double.infinity).toDouble());
  }

  static bool isOverspent({required double limit, required double spent}) =>
      spent > limit;

  /// Nepal FY approx on AD calendar: Shrawan ~ Jul 16. v1 bucket: Jul-Jun.
  /// Returns FY start year (e.g. Oct 2026 -> FY 2026/27, start 2026).
  static int fyStartYear(DateTime date) =>
      date.month >= 7 ? date.year : date.year - 1;

  /// FY month 1..12 where 1 = Shrawan (Jul). Jul->1 ... Jun->12.
  static int fyMonth(DateTime date) =>
      ((date.month - 7 + 12) % 12) + 1;

  static String fyLabel(DateTime date) {
    final s = fyStartYear(date);
    return 'FY $s/${(s + 1).toString().substring(2)}';
  }

  static double netWorth({
    required List<double> accountBalances,
    required double receivableOutstanding,
    required double payableOutstanding,
  }) {
    return Money.sum2([
      receivableOutstanding,
      -payableOutstanding,
      ...accountBalances,
    ]);
  }
}
