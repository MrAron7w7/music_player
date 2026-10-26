import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:music_app/data/services/app_cache.dart';

void main() {
  late Directory directory;
  late Box box;
  late AppCache cache;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('melody_cache_test');
    Hive.init(directory.path);
  });

  setUp(() async {
    box = await Hive.openBox('cache_test');
    cache = AppCache(box);
  });

  tearDown(() async {
    await box.clear();
    await box.close();
  });

  tearDownAll(() async {
    await Hive.deleteBoxFromDisk('cache_test', path: directory.path);
    await directory.delete(recursive: true);
  });

  test('guarda y recupera mapas con listas y valores nulos', () async {
    await cache.put('song', {
      'id': 'abc',
      'title': 'Hola',
      'album': null,
      'artists': ['A', 'B'],
      'durationSeconds': 120,
    });

    final raw = cache.get<Object>('song');
    expect(raw, isA<Map>());
    final map = Map<String, dynamic>.from(raw! as Map);
    expect(map['id'], 'abc');
    expect(map['album'], isNull);
    expect((map['artists'] as List).first, 'A');
  });

  test('respeta el ttl y el límite de entradas', () async {
    await cache.put('expired', 1, ttl: const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cache.get<int>('expired'), isNull);

    for (var i = 0; i < 6; i++) {
      await cache.put('key$i', i, maxEntries: 3);
    }
    expect(box.length, lessThanOrEqualTo(3));
  });

  test('los límites son por categoría y no borran otras claves', () async {
    for (var i = 0; i < 3; i++) {
      await cache.put('song:$i', i, maxEntries: 3);
    }
    await cache.put('lyrics:uno', 7, maxEntries: 3);
    await cache.put('song:tres', 3, maxEntries: 3);

    expect(cache.get<int>('lyrics:uno'), 7);
    expect(box.length, 4);
  });
}
