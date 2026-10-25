class TxnRow {
  final String id;
  final String accountName;
  final String? categoryName;
  final String kind;
  final double amount;
  final DateTime date;

  /// For `kind == 'transfer'`: 'out' from the source wallet or 'in' to the
  /// destination wallet. Null on legacy transfer rows.
  final String? transferDirection;

  /// Loan principal movements are cash movements, not income/expense.
  final bool excludedFromCashflow;

  TxnRow({
    required this.id,
    required this.accountName,
    required this.kind,
    required this.amount,
    required this.date,
    this.categoryName,
    this.transferDirection,
    this.excludedFromCashflow = false,
  });

  bool get isTransferIn =>
      kind == 'transfer' && transferDirection == 'in';
  bool get isTransferOut =>
      kind == 'transfer' && transferDirection == 'out';
}
