class BudgetRow {
  final String id;
  final String categoryName;
  final int fyYear;
  final int fyMonth;
  final double limit;
  double spent;

  BudgetRow({
    required this.id,
    required this.categoryName,
    required this.fyYear,
    required this.fyMonth,
    required this.limit,
    this.spent = 0,
  });
}
