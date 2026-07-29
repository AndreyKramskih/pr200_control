// lib/services/config_manager.dart (без path_provider)
import 'dart:convert';
import 'dart:io';
import '../models/config_model.dart';

class ConfigManager {
  static const String configsFolder = 'configs';
  static const String activeConfigFile = 'active_config.txt';

  // Получить базовую директорию
  static String _getBaseDir() {
    if (Platform.isAndroid) {
      return '/data/data/org.systherm.pr200/files';
    } else {
      return Directory.current.path;
    }
  }

  // Сохранить конфигурацию
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
      print('✅ Конфиг сохранен: $fileName');
    } catch (e) {
      print('❌ Ошибка сохранения конфига: $e');
      rethrow;
    }
  }

  // Получить список сохраненных конфигураций
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
      print('❌ Ошибка получения списка конфигов: $e');
      return [];
    }
  }

  // Загрузить конфигурацию по имени
  static Future<ConfigModel?> loadConfig(String name) async {
    try {
      final baseDir = _getBaseDir();
      final file = File('$baseDir/$configsFolder/$name');
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ConfigModel.fromJson(json);
    } catch (e) {
      print('❌ Ошибка загрузки конфига $name: $e');
      return null;
    }
  }

  // Активировать конфигурацию
  static Future<void> setActiveConfig(String name) async {
    try {
      final baseDir = _getBaseDir();
      final file = File('$baseDir/$activeConfigFile');
      await file.writeAsString(name);
      print('✅ Активный конфиг: $name');
    } catch (e) {
      print('❌ Ошибка активации конфига: $e');
      rethrow;
    }
  }

  // Получить активную конфигурацию
  static Future<String?> getActiveConfig() async {
    try {
      final baseDir = _getBaseDir();
      final file = File('$baseDir/$activeConfigFile');
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      print('❌ Ошибка получения активного конфига: $e');
      return null;
    }
  }

  // Удалить конфигурацию
  static Future<void> deleteConfig(String name) async {
    try {
      final baseDir = _getBaseDir();
      final file = File('$baseDir/$configsFolder/$name');
      if (await file.exists()) {
        await file.delete();
        print('✅ Конфиг удален: $name');
      }
    } catch (e) {
      print('❌ Ошибка удаления конфига $name: $e');
      rethrow;
    }
  }

  // Проверить, существует ли конфигурация
  static Future<bool> configExists(String name) async {
    try {
      final baseDir = _getBaseDir();
      final file = File('$baseDir/$configsFolder/$name');
      return await file.exists();
    } catch (e) {
      return false;
    }
  }
}
