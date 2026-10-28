import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'l10n/app_localizations.dart';

import 'src/core/cache/cache_service.dart';
import 'src/core/cache/outbox.dart';
import 'src/core/theme/app_theme.dart';
import 'src/features/auth/auth_gate.dart';
import 'src/features/home/home_shell.dart';

const supaUrl = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://aldbvbpbittvhkecnfpx.supabase.co');
const supaAnon = String.fromEnvironment('SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_LAdCM3lSdKAenADMUHGZ8Q_j5khG1DY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Offline read cache + write outbox. Failures here never block startup.
  try {
    await CacheService.init();
    await Outbox.init();
  } catch (_) {}
  await Supabase.initialize(url: supaUrl, publishableKey: supaAnon);
  // Cache and outbox are namespaced per user so a shared device cannot leak
  // one account's rows or replay its queued writes under another account.
  final userId = Supabase.instance.client.auth.currentUser?.id;
  await CacheService.setUser(userId);
  await Outbox.setUser(userId);
  runApp(const ProviderScope(child: NHisabApp()));
}

class NHisabApp extends StatelessWidget {
  const NHisabApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'nHisab',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('ne'),
      ],
      home: const AuthGate(child: HomeShell()),
    );
  }
}
