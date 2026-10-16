import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_service.dart';
import 'categories_provider.dart';
import 'category_form.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'addCat',
        tooltip: 'Add category',
        onPressed: () => showDialog(
            context: context,
            builder: (_) => const CategoryFormDialog()),
        child: const Icon(Icons.add),
      ),
      body: catsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Supabase error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No categories yet. Tap + to add one.',
                        textAlign: TextAlign.center)));
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final c = list[i];
              return ListTile(
                leading: Icon(c.kind == 'income'
                    ? Icons.trending_up
                    : Icons.trending_down),
                title: Text(c.name),
                subtitle: Text(c.kind),
                trailing: IconButton(
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  tooltip: 'Archive category',
                  onPressed: () async {
                    await Supabase.instance.client
                        .from('categories')
                        .update({
                      'deleted_at': DateTime.now().toIso8601String()
                    }).eq('id', c.id);
                    await AuditLog.write(
                        table: 'categories',
                        rowId: c.id,
                        action: 'archive');
                    ref.invalidate(categoriesProvider);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
