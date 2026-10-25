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

  test('Future loans accrue zero days, not backwards', () {
    final start = DateTime(2026, 11, 1);
    final today = DateTime(2026, 10, 15);
    expect(LoanCalculator.dueDays(start: start, today: today), 0);
    expect(
      LoanCalculator.interest(perDayAmount: 750, dueDaysCount: 0),
      0,
    );
  });

  test('Interest is capped at principal and dues is unpaid interest only', () {
    expect(
      LoanCalculator.cappedInterest(principal: 1000, interestAmount: 2500),
      1000,
    );
    expect(
      LoanCalculator.dues(interest: 1000, interestPaid: 400),
      600,
    );
    // A principal-only payment must not reduce unpaid interest.
    expect(
      LoanCalculator.dues(interest: 1000, interestPaid: 0),
      1000,
    );
    expect(
      LoanCalculator.outstanding(
          principal: 1000, interest: 1000, totalPaid: 1000),
      1000,
    );
    expect(
      LoanCalculator.outstanding(
          principal: 1000, interest: 1000, totalPaid: 2500),
      0,
    );
  });

  test('splitPayment allocates interest first, caps principal, returns excess',
      () {
    final start = DateTime(2026, 1, 1);
    final payDate = DateTime(2026, 3, 11); // 69 days

    final normal = LoanCalculator.splitPayment(
      payment: 500,
      perDayAmount: 1,
      start: start,
      payDate: payDate,
      prevInterestPaid: 0,
      principal: 1000,
    );
    expect(normal.interestPart, 69);
    expect(normal.principalPart, 431);
    expect(normal.excess, 0);

    final principalOnly = LoanCalculator.splitPayment(
      payment: 500,
      perDayAmount: 1,
      start: start,
      payDate: payDate,
      prevInterestPaid: 69,
      principal: 1000,
    );
    expect(principalOnly.interestPart, 0);
    expect(principalOnly.principalPart, 500);
    expect(principalOnly.excess, 0);

    final over = LoanCalculator.splitPayment(
      payment: 1500,
      perDayAmount: 1,
      start: start,
      payDate: payDate,
      prevInterestPaid: 0,
      principal: 1000,
    );
    expect(over.interestPart, 69);
    expect(over.principalPart, 1000);
    expect(over.excess, 431);

    final capped = LoanCalculator.splitPayment(
      payment: 1500,
      perDayAmount: 100,
      start: start,
      payDate: DateTime(2026, 1, 21), // 20 days -> 2000 raw interest
      prevInterestPaid: 0,
      principal: 1000,
    );
    expect(capped.interestPart, 1000);
    expect(capped.principalPart, 500);
    expect(capped.excess, 0);
  });
}
