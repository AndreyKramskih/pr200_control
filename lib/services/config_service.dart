import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/config_model.dart';

class ConfigService {
  static const String configFileName = 'config.json';

  Future<String> _getAppDirectory() async {
    if (Platform.isAndroid) {
      final externalDir =
          '/storage/emulated/0/Android/data/com.example.pr200_control/files';
      try {
        final dir = Directory(externalDir);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return externalDir;
      } catch (e) {
        print('⚠️ Не удалось создать папку в $externalDir: $e');
        return '/data/data/com.example.pr200_control/files';
      }
    } else if (Platform.isIOS) {
      return '${Directory.systemTemp.path}/Documents';
    } else {
      return Directory.current.path;
    }
  }

  Future<ConfigModel> loadConfig() async {
    try {
      final appDir = await _getAppDirectory();
      final file = File('$appDir/$configFileName');

      print('🔍 Поиск конфига в: ${file.path}');

      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        print('✅ Конфиг загружен из локального хранилища');
        return ConfigModel.fromJson(json);
      }

      print('⚠️ Локальный конфиг не найден, загружаю из assets');
      final assetConfig = await _loadAssetConfig();
      if (assetConfig != null) {
        print('✅ Конфиг загружен из assets');
        await _saveLocalConfig(assetConfig);
        return assetConfig;
      }

      print('⚠️ Конфиг не найден, создаю по умолчанию');
      final defaultConfig = _createDefaultConfig();
      await _saveLocalConfig(defaultConfig);
      return defaultConfig;
    } catch (e) {
      print('❌ Ошибка загрузки конфига: $e');
      return _createDefaultConfig();
    }
  }

  Future<ConfigModel?> _loadAssetConfig() async {
    try {
      final content = await rootBundle.loadString('assets/config.json');
      final json = jsonDecode(content) as Map<String, dynamic>;
      print('📄 Конфиг загружен успешно');
      return ConfigModel.fromJson(json);
    } catch (e) {
      print('⚠️ Ошибка загрузки конфига из assets: $e');
      return null;
    }
  }

  Future<void> _saveLocalConfig(ConfigModel config) async {
    try {
      final appDir = await _getAppDirectory();
      final dir = Directory(appDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        print('📁 Создана папка: $appDir');
      }

      final file = File('$appDir/$configFileName');
      final jsonString = jsonEncode(config.toJson());
      await file.writeAsString(jsonString, encoding: utf8);
      print('✅ Конфиг сохранен: ${file.path}');
    } catch (e) {
      print('❌ Ошибка сохранения конфига: $e');
    }
  }

  ConfigModel _createDefaultConfig() {
    return ConfigModel(
      projectName: 'ИТП №1',
      modbusServer: ModbusServer(
        ip: '192.168.101.250',
        port: 502,
        slaveId: 16,
        timeout: 3,
        retries: 3,
      ),
      systems: {
        'system1': SystemConfig(
          name: 'Система 1',
          icon: '🏠',
          submenus: {
            'sensors': SubmenuConfig(
              name: 'Датчики',
              icon: '🌡️',
              type: 'sensors',
              items: [
                ItemConfig(
                  name: 'Температура',
                  address: 1000,
                  type: 'float',
                  unit: '°C',
                ),
                ItemConfig(
                  name: 'Давление',
                  address: 1002,
                  type: 'float',
                  unit: 'бар',
                ),
              ],
            ),
          },
        ),
      },
      connection: ConnectionConfig(
        name: 'Подключение к оборудованию',
        icon: '🔌',
      ),
    );
  }

  Future<void> saveConfig(ConfigModel config) async {
    await _saveLocalConfig(config);
  }

  Future<bool> configExists() async {
    try {
      final appDir = await _getAppDirectory();
      final file = File('$appDir/$configFileName');
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  Future<String> getConfigPath() async {
    final appDir = await _getAppDirectory();
    return '$appDir/$configFileName';
  }
}
