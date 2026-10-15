class LoanRow {
  final String id;
  final String partyName;
  final double principal;
  final double rate;
  final String rateType;
  final int dayBase;
  final DateTime startDate;
  final String direction;
  final double paid;

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
  });
}
