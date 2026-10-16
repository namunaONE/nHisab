import 'package:flutter/material.dart';
import '../accounts/accounts_page.dart';
import '../audit/audit_page.dart';
import '../categories/categories_page.dart';
import '../import/import_page.dart';
import '../parties/parties_page.dart';
import '../payments/payments_page.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});
  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.wallet, 'Accounts', const AccountsPage()),
      (Icons.category_outlined, 'Categories', const CategoriesPage()),
      (Icons.people, 'Parties', const PartiesPage()),
      (Icons.payments, 'Payments', const PaymentsPage()),
      (Icons.history, 'Audit Trail', const AuditPage()),
      (Icons.upload, 'Import / Export', const ImportPage()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) {
          final (icon, label, page) = items[i];
          return ListTile(
            leading: Icon(icon),
            title: Text(label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => page)),
          );
        },
      ),
    );
  }
}
