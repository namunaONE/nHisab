class LoanRow {
  final String id;
  final String partyName;
  final double principal;
  final double rate;
  final String rateType;
  final int dayBase;
  final DateTime startDate;
  final String direction;

  /// Total of all live payments (interest + principal).
  final double paid;

  /// Interest component of [paid]. Dues must use this, never [paid].
  final double interestPaid;

  /// Principal component of [paid].
  final double principalPaid;

  LoanRow({
    required this.id,
    required this.partyName,
    required this.principal,
    required this.rate,
    required this.rateType,
    required this.dayBase,
    required this.startDate,
    required this.direction,
    required this.paid,
    this.interestPaid = 0,
    this.principalPaid = 0,
  });
}
