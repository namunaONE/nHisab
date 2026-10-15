class AccountRow {
  final String id;
  final String name;
  final String type;
  final double openingBalance;
  double computedBalance;

  AccountRow({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalance,
    this.computedBalance = 0,
  });
}
