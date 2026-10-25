import 'dart:math' as math;

import '../money/money.dart';

/// nHisab calculation engine.
/// Locked spec: Rate 0.18 = 18% annual decimal. DayBase 360 default.
/// Intermediate math is Decimal-exact via [Money]; public API unchanged.
class LoanCalculator {
  static double round2(double v) => (v * 100).round() / 100;

  static double annualRate({required double rate, required String rateType}) {
    switch (rateType) {
      case 'monthly':
        return rate * 12;
      case 'daily':
        return rate * 360;
      default:
        return rate;
    }
  }

  /// Whole days accrued since [start]. Never negative.
  ///
  /// A loan that starts in the future has zero accrued interest. Using
  /// `abs()` here used to accrue interest backwards before disbursement.
  static int dueDays({required DateTime start, required DateTime today}) {
    final days =
        today.difference(DateTime(start.year, start.month, start.day)).inDays;
    return days < 0 ? 0 : days;
  }

  static bool isProjected({required DateTime start, required DateTime today}) {
    return start.isAfter(DateTime(today.year, today.month, today.day));
  }

  /// Civil Code 2074 s.481 caps cumulative interest at the principal.
  /// Keep the raw accrual visible for reconciliation, but never charge more
  /// than the principal as interest.
  static double cappedInterest({
    required double principal,
    required double interestAmount,
  }) {
    if (principal <= 0 || interestAmount <= 0) return 0;
    return math.min(round2(interestAmount), round2(principal));
  }

  /// Interest still unpaid. Principal payments must not reduce this figure.
  static double dues({
    required double interest,
    required double interestPaid,
  }) {
    final remaining = round2(interest - interestPaid);
    return remaining < 0 ? 0 : remaining;
  }

  /// Total outstanding = unpaid principal + unpaid interest.
  static double outstanding({
    required double principal,
    required double interest,
    required double totalPaid,
  }) {
    final remaining = round2(principal + interest - totalPaid);
    return remaining < 0 ? 0 : remaining;
  }

  static double perDay({
    required double principal,
    required double annualRateDecimal,
    required int dayBase,
  }) {
    if (annualRateDecimal == 0) return 0;
    return Money.perDay(
        principal: principal,
        annualRateDecimal: annualRateDecimal,
        dayBase: dayBase);
  }

  static double interest({
    required double perDayAmount,
    required int dueDaysCount,
  }) {
    return Money.interest(
        perDayAmount: perDayAmount, dueDaysCount: dueDaysCount);
  }

  static double total({
    required double principal,
    required double interestAmount,
    required double paid,
  }) {
    return round2(principal + interestAmount - paid);
  }

  static double emi({
    required double principal,
    required double annualRatePct,
    required int months,
  }) {
    if (months <= 0) return 0;
    final r = annualRatePct / 12 / 100;
    if (r == 0) return round2(principal / months);
    final pow = math.pow(1 + r, months);
    return round2(principal * r * pow / (pow - 1));
  }

  /// Interest-first split for a payment on date D.
  ///
  /// [principal] and [prevPrincipalPaid] are optional. When supplied, accrued
  /// interest is capped at the principal (Civil Code s.481) and the principal
  /// portion cannot exceed the unpaid principal. Any money left over is
  /// returned as [excess] so the caller can reject an overpayment instead of
  /// silently discarding it.
  static ({double interestPart, double principalPart, double excess})
      splitPayment({
    required double payment,
    required double perDayAmount,
    required DateTime start,
    required DateTime payDate,
    required double prevInterestPaid,
    double? principal,
    double prevPrincipalPaid = 0,
  }) {
    final days = dueDays(start: start, today: payDate);
    var interestDue = round2(perDayAmount * days);
    if (principal != null && principal > 0) {
      interestDue =
          cappedInterest(principal: principal, interestAmount: interestDue);
    }
    final remainingInterest =
        (interestDue - prevInterestPaid).clamp(0, double.infinity).toDouble();
    final interestPart = payment.clamp(0, remainingInterest).toDouble();
    final requestedPrincipal = round2(payment - interestPart);
    var principalPart = requestedPrincipal;
    if (principal != null && principal > 0) {
      final unpaidPrincipal =
          (principal - prevPrincipalPaid).clamp(0, double.infinity).toDouble();
      if (principalPart > unpaidPrincipal) {
        principalPart = round2(unpaidPrincipal);
      }
    }
    final excess = round2(payment - interestPart - principalPart);
    return (
      interestPart: round2(interestPart),
      principalPart: round2(principalPart),
      excess: excess < 0 ? 0 : excess,
    );
  }
}
