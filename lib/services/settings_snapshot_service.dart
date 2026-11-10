// lib/services/settings_snapshot_service.dart
import 'dart:convert';
import 'dart:io';
import 'logger_service.dart';

/// Глобальные снимки настроек.
/// Один общий список — можно применить снимок с одного объекта на любом другом,
/// где та же программа ПЛК (совпадают адреса параметров).
class SettingsSnapshotService {
  static const String _fileName = 'settings_snapshots.json';

  static Future<String> _getAppDir() async {
    if (Platform.isAndroid) {
      final dir =
          '/storage/emulated/0/Android/data/com.example.pr200_control/files';
      final d = Directory(dir);
      if (!await d.exists()) await d.create(recursive: true);
      return dir;
    }
    return Directory.current.path;
  }

  static Future<File> _getFile() async {
    final appDir = await _getAppDir();
    return File('$appDir/$_fileName');
  }

  /// Структура файла:
  /// {
  ///   "snapshots": {
  ///     "Типовой": {
  ///       "saved_at": "...",
  ///       "projectName": "ОЛ_19",
  ///       "systemId": "...",
  ///       "submenuId": "...",
  ///       "values": { "515": 6, ... }
  ///     },
  ///     ...
  ///   }
  /// }
  static Future<Map<String, dynamic>> _readAll() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return {'snapshots': {}};
      final content = await file.readAsString();
      if (content.isEmpty) return {'snapshots': {}};
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        decoded.putIfAbsent('snapshots', () => <String, dynamic>{});
        return decoded;
      }
      return {'snapshots': {}};
    } catch (e) {
      LoggerService().log('❌ Ошибка чтения снимков: $e', level: LogLevel.error);
      return {'snapshots': {}};
    }
  }

  static Future<void> _writeAll(Map<String, dynamic> data) async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      LoggerService().log('❌ Ошибка записи снимков: $e', level: LogLevel.error);
      rethrow;
    }
  }

  /// Сохранить снимок (в общий пул).
  static Future<void> saveSnapshot({
    required String projectName,
    required String systemId,
    required String submenuId,
    required Map<String, dynamic> values,
    required String snapshotName,
  }) async {
    final all = await _readAll();
    final snapshots = (all['snapshots'] as Map).cast<String, dynamic>();

    snapshots[snapshotName] = {
      'saved_at': DateTime.now().toIso8601String(),
      'projectName': projectName,
      'systemId': systemId,
      'submenuId': submenuId,
      'values': values,
    };

    all['snapshots'] = snapshots;
    await _writeAll(all);

    LoggerService().log(
      '✅ Снимок "$snapshotName" сохранён (проект: $projectName)',
    );
  }

  /// Список всех снимков с описанием: {name: {saved_at, projectName}}
  static Future<Map<String, Map<String, String>>> listSnapshots() async {
    final all = await _readAll();
    final snapshots = (all['snapshots'] as Map).cast<String, dynamic>();
    final result = <String, Map<String, String>>{};
    snapshots.forEach((name, raw) {
      if (raw is! Map) return;
      result[name] = {
        'saved_at': raw['saved_at']?.toString() ?? '',
        'projectName': raw['projectName']?.toString() ?? '',
      };
    });
    return result;
  }

  /// Загрузить снимок по имени (без привязки к текущему проекту).
  static Future<Map<String, dynamic>?> loadSnapshot({
    required String snapshotName,
  }) async {
    final all = await _readAll();
    final snapshots = (all['snapshots'] as Map).cast<String, dynamic>();
    final snap = (snapshots[snapshotName] as Map?)?.cast<String, dynamic>();
    if (snap == null) return null;
    return (snap['values'] as Map?)?.cast<String, dynamic>();
  }

  /// Удалить снимок.
  static Future<void> deleteSnapshot(String snapshotName) async {
    final all = await _readAll();
    final snapshots = (all['snapshots'] as Map).cast<String, dynamic>();
    snapshots.remove(snapshotName);
    all['snapshots'] = snapshots;
    await _writeAll(all);
  }
}
