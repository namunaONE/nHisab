import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/profiles_provider.dart';
import '../auth/session_provider.dart';
import '../budgets/budgets_page.dart';
import '../dashboard/dashboard_page.dart';
import '../loans/loan_form.dart';
import '../more/more_page.dart';
import '../notifications/notifications_provider.dart';
import '../parties/party_form.dart';
import '../../core/cache/connectivity_provider.dart';
import '../../core/cache/outbox.dart';
import '../accounts/accounts_provider.dart';
import '../transactions/transactions_provider.dart';
import '../payments/payment_form.dart';
import '../transactions/transactions_page.dart';
import 'ledger_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int idx = 0;
  RealtimeChannel? _notifChannel;

  @override
  void initState() {
    super.initState();
    // Realtime bell: invalidate notification providers on every change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifChannel = subscribeNotifications(ref);
    });
    // Flush the offline outbox whenever connectivity returns.
    ref.listenManual(
      isOfflineProvider,
      (prev, next) {
        if (prev == true && next == false) {
          Outbox.flush().then((r) {
            if (r.flushed > 0) {
              ref.invalidate(accountsProvider);
              ref.invalidate(transactionsProvider);
            }
          });
        }
      },
      fireImmediately: false,
    );
  }

  @override
  void dispose() {
    if (_notifChannel != null) {
      Supabase.instance.client.removeChannel(_notifChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = const [
      DashboardPage(),
      LedgerPage(),
      TransactionsPage(),
      BudgetsPage(),
      MorePage(),
    ];
    final offline = ref.watch(isOfflineProvider);
    final canWrite = ref.watch(canWriteProvider);
    return Scaffold(
      body: Column(
        children: [
          if (offline)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline - showing cached data. Some entries queue; payments require a connection.',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: pages[idx]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(
              icon: Icon(Icons.table_chart), label: 'Ledger'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long), label: 'Txns'),
          NavigationDestination(
              icon: Icon(Icons.savings), label: 'Budgets'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
      floatingActionButton: idx == 1 && canWrite
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(heroTag: 'p', tooltip: 'Add party', onPressed: () => showDialog(context: context, builder: (_) => const PartyFormDialog()), child: const Icon(Icons.person_add)),
                const SizedBox(height: 8),
                FloatingActionButton.small(heroTag: 'l', tooltip: 'Add loan', onPressed: () => showDialog(context: context, builder: (_) => const LoanFormDialog()), child: const Icon(Icons.add_card)),
                const SizedBox(height: 8),
                FloatingActionButton(heroTag: 'pay', tooltip: 'Record payment', onPressed: () => showDialog(context: context, builder: (_) => const PaymentFormDialog()), child: const Icon(Icons.add)),
              ],
            )
          : null,
    );
  }
}

class UserMenu extends ConsumerWidget {
  const UserMenu({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return PopupMenuButton(
      icon: const Icon(Icons.account_circle),
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text(email)),
        const PopupMenuItem(value: 'out', child: Text('Sign out')),
      ],
      onSelected: (v) async {
        if (v == 'out') {
          await signOutAndClear();
          ref.invalidate(authStateProvider);
          ref.invalidate(profileProvider);
        }
      },
    );
  }
}
