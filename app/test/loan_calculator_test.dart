import 'package:flutter_test/flutter_test.dart';
import 'package:nhisab/src/core/calculator/loan_calculator.dart';

void main() {
  test('Row1 Saroj Poudel matches sheet', () {
    const p = 1500000.0;
    const rate = 0.18;
    final start = DateTime(2026, 6, 19);
    final today = DateTime(2026, 10, 15);
    final days = LoanCalculator.dueDays(start: start, today: today);
    expect(days, 118);
    final perDay = LoanCalculator.perDay(principal: p, annualRateDecimal: rate, dayBase: 360);
    expect(perDay, 750.0);
    final interest = LoanCalculator.interest(perDayAmount: perDay, dueDaysCount: days);
    expect(interest, 88500.0);
    final total = LoanCalculator.total(principal: p, interestAmount: interest, paid: 0);
    expect(total, 1588500.0);
  });

  test('EMI reducing balance sanity', () {
    final emi = LoanCalculator.emi(principal: 1000000, annualRatePct: 10, months: 12);
    expect(emi, greaterThan(87000));
    expect(emi, lessThan(89000));
  });
}
