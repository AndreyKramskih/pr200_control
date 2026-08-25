// lib/services/config_manager.dart
import 'dart:convert';
import 'dart:io';
import '../models/config_model.dart';
import 'logger_service.dart';

class ConfigManager {
  static const String configsFolder = 'configs';
  static const String activeConfigFile = 'active_config.txt';

  /// Получить базовую директорию
  static String _getBaseDir() {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Android/data/com.example.pr200_control/files';
    } else {
      return Directory.current.path;
    }
  }

  /// Сохранить конфигурацию
  static Future<void> saveConfig(ConfigModel config, {String? name}) async {
    try {
      final baseDir = _getBaseDir();
      final configDir = Directory('$baseDir/$configsFolder');
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }

      final fileName =
          name ?? 'config_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${configDir.path}/$fileName');
      await file.writeAsString(jsonEncode(config.toJson()));

      LoggerService().log('✅ Конфиг сохранен: $fileName');
    } catch (e) {
      LoggerService().log(
        '❌ Ошибка сохранения конфига: $e',
        level: LogLevel.error,
      );
      rethrow;
    }
  }

  /// Получить список сохраненных конфигураций
  static Future<List<String>> getConfigList() async {
    try {
      final baseDir = _getBaseDir();
      final configDir = Directory('$baseDir/$configsFolder');
      if (!await configDir.exists()) return [];

      final files = await configDir.list().toList();
      return files
          .where((f) => f.path.endsWith('.json'))
          .map((f) => f.path.split(Platform.pathSeparator).last)
          .toList();
    } catch (e) {
      LoggerService().log(
        '❌ Ошибка получения списка конфигов: $e',
        level: LogLevel.error,
      );
      return [];
    }
  }

  /// Загрузить конфигурацию по имени
  static Future<ConfigModel?> loadConfig(String name) async {
    try {
      final baseDir = _getBaseDir();
      final file = File('$baseDir/$configsFolder/$name');
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ConfigModel.fromJson(json);
    } catch (e) {
      LoggerService().log(
        '❌ Ошибка загрузки конфига $name: $e',
        level: LogLevel.error,
      );
      return null;
    }
  }

  /// Активировать конфигурацию
  static Future<void> setActiveConfig(String name) async {
    try {
      final baseDir = _getBaseDir();
      final file = File('$baseDir/$activeConfigFile');
      await file.writeAsString(name);
      LoggerService().log('✅ Активный конфиг: $name');
    } catch (e) {
      LoggerService().log(
        '❌ Ошибка активации конфига: $e',
        level: LogLevel.error,
      );
      rethrow;
    }
  }

  /// Получить активную конфигурацию
  static Future<String?> getActiveConfig() async {
    try {
      final baseDir = _getBaseDir();
      final file = File('$baseDir/$activeConfigFile');
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      LoggerService().log(
        '❌ Ошибка получения активного конфига: $e',
        level: LogLevel.error,
      );
      return null;
    }
  }

  /// Удалить конфигурацию
  static Future<void> deleteConfig(String name) async {
    try {
      final baseDir = _getBaseDir();
      final file = File('$baseDir/$configsFolder/$name');
      if (await file.exists()) {
        await file.delete();
        LoggerService().log('✅ Конфиг удален: $name');
      }
    } catch (e) {
      LoggerService().log(
        '❌ Ошибка удаления конфига $name: $e',
        level: LogLevel.error,
      );
      rethrow;
    }
  }
}
