class TxnRow {
  final String id;
  final String accountName;
  final String? categoryName;
  final String kind;
  final double amount;
  final DateTime date;

  TxnRow({
    required this.id,
    required this.accountName,
    required this.kind,
    required this.amount,
    required this.date,
    this.categoryName,
  });
}
