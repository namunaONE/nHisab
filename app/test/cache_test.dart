import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nhisab/src/core/cache/cache_service.dart';
import 'package:nhisab/src/core/cache/outbox.dart';

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('nhisab_cache_test');
    await CacheService.init(path: tmp.path);
    await Outbox.init(path: tmp.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('fetchOrCache returns fresh rows and caches them', () async {
    final rows = [
      {'id': 'a1', 'name': 'Cash'},
      {'id': 'a2', 'name': 'Bank'},
    ];
    final first = await CacheService.fetchOrCache(
      key: 'test:accounts',
      fetch: () async => rows,
    );
    expect(first.fromCache, isFalse);
    expect(first.rows.length, 2);

    // Network failure falls back to cache.
    final second = await CacheService.fetchOrCache(
      key: 'test:accounts',
      fetch: () async => throw Exception('offline'),
    );
    expect(second.fromCache, isTrue);
    expect(second.rows.length, 2);
  });

  test('fetchOrCache rethrows when nothing cached', () async {
    expect(
      () => CacheService.fetchOrCache(
        key: 'test:missing',
        fetch: () async => throw Exception('offline'),
      ),
      throwsException,
    );
  });

  test('parseAll skips corrupt rows', () async {
    final parsed = CacheService.parseAll<String>(
      [
        {'name': 'ok'},
        'not-a-map',
        {'nope': 1},
      ],
      (m) => (m['name'] ?? '').toString(),
    );
    expect(parsed, ['ok', '']);
  });

  test('Outbox enqueue + pendingCount', () async {
    final before = Outbox.pendingCount;
    await Outbox.enqueue(
        table: 'transactions', data: {'amount': 100, 'kind': 'expense'});
    expect(Outbox.pendingCount, before + 1);
  });
}
