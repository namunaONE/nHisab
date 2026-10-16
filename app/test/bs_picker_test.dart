import 'package:bikram_sambat/bikram_sambat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhisab/src/core/dates/bs_picker.dart';

void main() {
  test('AD -> BS -> AD round-trips without drift', () {
    for (final ad in [
      DateTime(2026, 10, 15),
      DateTime(2023, 4, 14),
      DateTime(2024, 1, 1),
      DateTime(2000, 1, 1),
    ]) {
      final back = BikramSambat.fromDateTime(ad).toDateTime();
      expect(back.year, ad.year);
      expect(back.month, ad.month);
      expect(back.day, ad.day);
    }
  });

  test('Known anchors map to expected BS dates', () {
    // Nepali New Year 2080 (Friday) and sheet Today.
    final ny = BikramSambat.fromDateTime(DateTime(2023, 4, 14));
    expect((ny.year, ny.month, ny.day), (2080, 1, 1));
    final today = BikramSambat.fromDateTime(DateTime(2026, 10, 15));
    expect((today.year, today.month, today.day), (2083, 6, 29));
  });

  test('BS month lengths are sane (29-32 days)', () {
    for (var m = 1; m <= 12; m++) {
      final days = BsPicker.daysInBsMonth(2083, m);
      expect(days, inInclusiveRange(29, 32));
    }
  });

  test('Preview labels AD and BS shapes', () {
    expect(BsPicker.preview(DateTime(2026, 10, 15), false), '2026/10/15');
    expect(BsPicker.preview(DateTime(2026, 10, 15), true), '2083-06-29 BS');
  });
}
