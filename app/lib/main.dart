import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/core/cache/cache_service.dart';
import 'src/core/cache/outbox.dart';
import 'src/core/theme/app_theme.dart';
import 'src/features/auth/auth_gate.dart';
import 'src/features/home/home_shell.dart';

const supaUrl = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://qcbxurqxmnkzgsfpaesz.supabase.co');
const supaAnon = String.fromEnvironment('SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_49uKhtmYBJMFdpGyTYWjfg_50pfzrLN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Offline read cache + write outbox. Failures here never block startup.
  try {
    await CacheService.init();
    await Outbox.init();
  } catch (_) {}
  await Supabase.initialize(url: supaUrl, publishableKey: supaAnon);
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
      home: const AuthGate(child: HomeShell()),
    );
  }
}
