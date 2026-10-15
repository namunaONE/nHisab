import 'package:bikram_sambat/bikram_sambat.dart';

/// BS helpers. Storage is always AD DateTime. Display AD + BS.
class BsDate {
  static String toBsString(DateTime ad) {
    try {
      final bs = ad.toBikramSambat();
      return '${bs.year}-${bs.month.toString().padLeft(2, '0')}-${bs.day.toString().padLeft(2, '0')} BS';
    } catch (_) {
      return '-- BS';
    }
  }

  static String dual(DateTime ad) {
    final adStr =
        '${ad.year}-${ad.month.toString().padLeft(2, '0')}-${ad.day.toString().padLeft(2, '0')} AD';
    return '$adStr | ${toBsString(ad)}';
  }
}
