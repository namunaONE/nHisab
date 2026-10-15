import 'package:flutter_test/flutter_test.dart';
import 'package:nhisab/src/core/money/money.dart';

void main() {
  test('0.1 + 0.2 sums exactly (no binary drift)', () {
    expect(Money.sum2([0.1, 0.2]), 0.3);
  });

  test('1000 x 0.07 accumulates exactly', () {
    expect(Money.sum2(List.filled(1000, 0.07)), 70.0);
  });

  test('Sheet identity 1500000*0.18/360 stays 750.00', () {
    expect(
        Money.perDay(
            principal: 1500000,
            annualRateDecimal: 0.18,
            dayBase: 360),
        750.0);
    expect(Money.interest(perDayAmount: 750.0, dueDaysCount: 118), 88500.0);
  });

  test('Exact-decimal halfway rounds half away (2.335 -> 2.34)', () {
    // Note: binary-double round2 gives 2.33 here (2.335 is 2.33499... in
    // binary). Money is exact, so halfway cases round up by design.
    expect(Money.round2(2.345), 2.35);
    expect(Money.round2(2.335), 2.34);
    expect(Money.round2(0.0), 0.0);
  });
}
