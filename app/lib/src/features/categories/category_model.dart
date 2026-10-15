class CategoryRow {
  final String id;
  final String kind;
  final String name;
  final String? icon;

  CategoryRow(
      {required this.id,
      required this.kind,
      required this.name,
      this.icon});
}
