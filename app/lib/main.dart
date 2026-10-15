import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/core/theme/app_theme.dart';
import 'src/features/auth/auth_gate.dart';
import 'src/features/home/home_shell.dart';

const supaUrl = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://qcbxurqxmnkzgsfpaesz.supabase.co');
const supaAnon = String.fromEnvironment('SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_49uKhtmYBJMFdpGyTYWjfg_50pfzrLN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supaUrl, anonKey: supaAnon);
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
