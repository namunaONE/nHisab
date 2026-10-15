import 'package:decimal/decimal.dart';
import 'package:rational/rational.dart';

/// Precise money math on top of `decimal` + `rational`.
/// All public values stay `double` rounded to 2dp so callers and the
/// NUMERIC(15,2) DB are unchanged — only the *intermediate* math is exact.
/// Positive-amount rounding matches Dart `(v*100).round()/100`
/// (half away from zero; Rational.round uses the same rule).
class Money {
  /// Exact 2dp round of a double without binary-float drift.
  static double round2(double v) {
    final Rational cents =
        Rational.parse(v.toString()) * Rational.fromInt(100);
    return cents.round().toDouble() / 100.0;
  }

  /// Exact sum of already-rounded amounts (footers, balances).
  /// Kills 0.1+0.2 style drift over hundreds of rows.
  static double sum2(Iterable<double> amounts) {
    var total = Decimal.zero;
    for (final a in amounts) {
      total += Decimal.parse(a.toString());
    }
    return total.round(scale: 2).toDouble();
  }

  /// PerDay = Principal * RateAnnual / DayBase, exact then 2dp.
  static double perDay({
    required double principal,
    required double annualRateDecimal,
    required int dayBase,
  }) {
    if (annualRateDecimal == 0) return 0;
    final Rational q = Rational.parse(principal.toString()) *
        Rational.parse(annualRateDecimal.toString()) *
        Rational.fromInt(1) /
        Rational.fromInt(dayBase);
    final Rational cents = q * Rational.fromInt(100);
    return cents.round().toDouble() / 100.0;
  }

  /// Interest = PerDay * days, exact then 2dp.
  static double interest({
    required double perDayAmount,
    required int dueDaysCount,
  }) {
    final Rational cents = Rational.parse(perDayAmount.toString()) *
        Rational.fromInt(dueDaysCount) *
        Rational.fromInt(100);
    return cents.round().toDouble() / 100.0;
  }
}
