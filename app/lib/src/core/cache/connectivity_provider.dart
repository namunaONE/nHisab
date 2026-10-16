import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live connectivity as a list of results (connectivity_plus v6 API).
final connectivityProvider =
    StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// True when the device has no usable connection.
/// Unknown/empty state counts as online so the app never blocks on startup.
final isOfflineProvider = Provider<bool>((ref) {
  final async = ref.watch(connectivityProvider);
  final results = async.valueOrNull;
  if (results == null || results.isEmpty) return false;
  return results.every((r) => r == ConnectivityResult.none);
});
