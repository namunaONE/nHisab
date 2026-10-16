import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/skeleton.dart';
import 'audit_provider.dart';

class AuditPage extends ConsumerStatefulWidget {
  const AuditPage({super.key});
  @override
  ConsumerState<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<AuditPage> {
  String? tableFilter;

  @override
  Widget build(BuildContext context) {
    final rowsAsync = ref.watch(auditProvider(tableFilter));
    final tablesAsync = ref.watch(auditTablesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Audit Trail')),
      body: Column(
        children: [
          tablesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (tables) {
              if (tables.isEmpty) return const SizedBox.shrink();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: tableFilter == null,
                      onSelected: (_) =>
                          setState(() => tableFilter = null),
                    ),
                    const SizedBox(width: 8),
                    for (final t in tables)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(t),
                          selected: tableFilter == t,
                          onSelected: (_) =>
                              setState(() => tableFilter = t),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: rowsAsync.when(
              loading: () => const SkeletonList(itemCount: 6),
              error: (e, _) => ErrorState(
                message: e.toString(),
                onRetry: () =>
                    ref.invalidate(auditProvider(tableFilter)),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.history,
                    title: 'No audit entries yet',
                    subtitle:
                        'Every insert, update and archive is recorded here.',
                  );
                }
                return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return ListTile(
                      leading: Icon(
                        _actionIcon(r.action),
                        color: _actionColor(r.action, scheme),
                      ),
                      title: Text('${r.tableName} • ${r.action}'),
                      subtitle: Text(
                          '${r.createdAt.year}/${r.createdAt.month}/${r.createdAt.day} '
                          '${r.createdAt.hour.toString().padLeft(2, '0')}:'
                          '${r.createdAt.minute.toString().padLeft(2, '0')}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'insert':
        return Icons.add_circle_outline;
      case 'update':
        return Icons.edit_outlined;
      case 'archive':
        return Icons.archive_outlined;
      default:
        return Icons.history;
    }
  }

  Color _actionColor(String action, ColorScheme scheme) {
    switch (action) {
      case 'insert':
        return scheme.secondary;
      case 'archive':
        return scheme.error;
      default:
        return scheme.primary;
    }
  }
}
