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

  static int dueDays({required DateTime start, required DateTime today}) {
    return today.difference(DateTime(start.year, start.month, start.day)).inDays.abs();
  }

  static bool isProjected({required DateTime start, required DateTime today}) {
    return start.isAfter(DateTime(today.year, today.month, today.day));
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
  static ({double interestPart, double principalPart}) splitPayment({
    required double payment,
    required double perDayAmount,
    required DateTime start,
    required DateTime payDate,
    required double prevInterestPaid,
  }) {
    final days = payDate.difference(DateTime(start.year, start.month, start.day)).inDays.abs();
    final interestDue = round2(perDayAmount * days);
    final remainingInterest = (interestDue - prevInterestPaid).clamp(0, double.infinity).toDouble();
    final interestPart = payment.clamp(0, remainingInterest).toDouble();
    final principalPart = round2(payment - interestPart);
    return (interestPart: round2(interestPart), principalPart: principalPart);
  }
}
