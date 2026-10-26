import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Caché persistente con TTL y límites por familia de claves.
///
/// Se guarda en una única caja de Hive para no tocar los datos del usuario
/// (favoritos, playlists, historial y ajustes quedan intactos). Los límites se
/// aplican por prefijo (`search:`, `lyrics:`, `color:`…) para que llenar una
/// categoría no vacíe las demás.
class AppCache {
  AppCache(this._box);

  final Box _box;

  static const _valueKey = 'v';
  static const _expiresKey = 'e';
  static const _createdKey = 'c';
  static const _globalMaxEntries = 700;

  final Map<String, int> _categoryCounts = {};
  final Set<String> _loadedCategories = {};

  T? get<T>(String key) {
    try {
      final raw = _box.get(key);
      if (raw is! Map) return null;
      final expiresAt = raw[_expiresKey];
      if (expiresAt is int &&
          DateTime.now().millisecondsSinceEpoch > expiresAt) {
        _box.delete(key);
        _forgetCategory(key);
        return null;
      }
      final value = raw[_valueKey];
      return value is T ? value : null;
    } catch (error) {
      debugPrint('Caché ilegible para $key: $error');
      return null;
    }
  }

  bool has(String key) => get<Object?>(key) != null;

  Future<void> put(
    String key,
    Object? value, {
    Duration ttl = const Duration(days: 7),
    int maxEntries = 500,
  }) async {
    if (value == null) return;
    try {
      final existed = _box.containsKey(key);
      final now = DateTime.now();
      await _box.put(key, {
        _valueKey: value,
        _expiresKey: now.add(ttl).millisecondsSinceEpoch,
        _createdKey: now.millisecondsSinceEpoch,
      });

      final prefix = _prefixOf(key);
      final label = prefix ?? '';
      if (_loadedCategories.contains(label)) {
        _categoryCounts[label] =
            (_categoryCounts[label] ?? 0) + (existed ? 0 : 1);
      } else {
        _categoryCounts[label] = await _countCategory(prefix);
        _loadedCategories.add(label);
      }

      if ((_categoryCounts[label] ?? 0) > maxEntries) {
        _categoryCounts[label] = await _pruneCategory(prefix, maxEntries);
      }

      if (_box.length > _globalMaxEntries) {
        await _pruneGlobal(_globalMaxEntries);
        _loadedCategories.clear();
        _categoryCounts.clear();
      }
    } catch (error) {
      // La caché nunca debe interrumpir la reproducción ni la navegación.
      debugPrint('No se pudo guardar en caché $key: $error');
    }
  }

  Future<void> remove(String key) async {
    try {
      final existed = _box.containsKey(key);
      await _box.delete(key);
      if (!existed) return;
      final label = _prefixOf(key) ?? '';
      if (_loadedCategories.contains(label)) {
        final current = _categoryCounts[label] ?? 1;
        _categoryCounts[label] = current > 0 ? current - 1 : 0;
      }
    } catch (error) {
      debugPrint('No se pudo borrar de caché $key: $error');
    }
  }

  Future<void> clear() async {
    try {
      await _box.clear();
      _loadedCategories.clear();
      _categoryCounts.clear();
    } catch (error) {
      debugPrint('No se pudo limpiar la caché: $error');
    }
  }

  Future<int> countWhere(String prefix) async {
    var count = 0;
    for (final key in _box.keys) {
      if (key is String && key.startsWith('$prefix:')) count++;
    }
    return count;
  }

  Future<void> clearWhere(String prefix) async {
    final keys = _box.keys
        .where((key) => key is String && key.startsWith('$prefix:'))
        .toList();
    try {
      await _box.deleteAll(keys);
      _loadedCategories.remove(prefix);
      _categoryCounts.remove(prefix);
    } catch (error) {
      debugPrint('No se pudo limpiar la caché $prefix: $error');
    }
  }

  /// Estimación del espacio que ocupan las respuestas guardadas.
  int estimatedBytes() {
    var total = 0;
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        final value = raw[_valueKey];
        try {
          total += value.toString().length;
        } catch (_) {}
      }
    }
    return total;
  }

  int get entryCount => _box.length;

  String? _prefixOf(String key) {
    final index = key.indexOf(':');
    return index <= 0 ? null : key.substring(0, index);
  }

  void _forgetCategory(String key) {
    final label = _prefixOf(key) ?? '';
    _loadedCategories.remove(label);
    _categoryCounts.remove(label);
  }

  bool _matches(dynamic key, String? prefix) {
    if (prefix == null) return true;
    return key is String && key.startsWith('$prefix:');
  }

  Future<int> _countCategory(String? prefix) async {
    var count = 0;
    for (final key in _box.keys) {
      if (_matches(key, prefix)) count++;
    }
    return count;
  }

  Future<int> _pruneCategory(String? prefix, int maxEntries) async {
    final entries = <({dynamic key, int created})>[];
    for (final key in _box.keys) {
      if (!_matches(key, prefix)) continue;
      final raw = _box.get(key);
      final created = raw is Map ? raw[_createdKey] : null;
      entries.add((key: key, created: created is int ? created : 0));
    }
    entries.sort((a, b) => a.created.compareTo(b.created));
    final excess = entries.length - maxEntries;
    for (var i = 0; i < excess; i++) {
      await _box.delete(entries[i].key);
    }
    return entries.length > maxEntries ? maxEntries : entries.length;
  }

  Future<void> _pruneGlobal(int maxEntries) async {
    final entries = <({dynamic key, int created})>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      final created = raw is Map ? raw[_createdKey] : null;
      entries.add((key: key, created: created is int ? created : 0));
    }
    entries.sort((a, b) => a.created.compareTo(b.created));
    final excess = entries.length - maxEntries;
    for (var i = 0; i < excess; i++) {
      await _box.delete(entries[i].key);
    }
  }
}
