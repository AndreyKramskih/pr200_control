import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/config_model.dart';

class ConfigService {
  static const String configFileName = 'config.json';

  // Получаем путь к директории приложения
  Future<String> _getAppDirectory() async {
    // Для Android используем внешнее хранилище
    if (Platform.isAndroid) {
      // Пробуем получить доступ к внешнему хранилищу
      final externalDir =
          '/storage/emulated/0/Android/data/com.example.pr200_control/files';
      // Проверяем, можем ли создать папку
      try {
        final dir = Directory(externalDir);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return externalDir;
      } catch (e) {
        print('⚠️ Не удалось создать папку в $externalDir: $e');
        // Если не получилось - используем внутреннее хранилище приложения
        return '/data/data/com.example.pr200_control/files';
      }
    } else if (Platform.isIOS) {
      return '${Directory.systemTemp.path}/Documents';
    } else {
      return Directory.current.path;
    }
  }

  // Загрузка конфигурации
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

  // Загрузка из assets
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

  // Сохранение в локальное хранилище
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
      // Не перевыбрасываем ошибку, чтобы приложение продолжало работать
    }
  }

  // ✅ МЕСТО 1: Создание конфига по умолчанию (добавляем projectName)
  ConfigModel _createDefaultConfig() {
    return ConfigModel(
      projectName: 'ИТП №1', // ✅ ДОБАВЛЯЕМ
      modbusServer: ModbusServer(
        ip: '192.168.1.100',
        port: 502,
        slaveId: 1,
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
            'settings': SubmenuConfig(
              name: 'Настройки',
              icon: '⚙️',
              type: 'settings',
              groups: [
                GroupConfig(
                  name: 'Основные параметры',
                  items: [
                    ItemConfig(
                      name: 'Параметр 1',
                      address: 500,
                      type: 'int',
                      unit: '%',
                      min: 0,
                      max: 100,
                      defaultValue: 50,
                    ),
                  ],
                ),
              ],
            ),
          },
        ),
        'system2': SystemConfig(
          name: 'Вентиляция',
          icon: '💨',
          submenus: {
            'sensors': SubmenuConfig(
              name: 'Датчики',
              icon: '🌡️',
              type: 'sensors',
              items: [
                ItemConfig(
                  name: 'Температура притока',
                  address: 2000,
                  type: 'float',
                  unit: '°C',
                ),
                ItemConfig(
                  name: 'Температура вытяжки',
                  address: 2002,
                  type: 'float',
                  unit: '°C',
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

  // ✅ МЕСТО 2: Сохранение конфига (публичный метод) - без изменений
  Future<void> saveConfig(ConfigModel config) async {
    await _saveLocalConfig(config);
  }

  // Проверка существования конфига
  Future<bool> configExists() async {
    try {
      final appDir = await _getAppDirectory();
      final file = File('$appDir/$configFileName');
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  // Получение пути к конфигу
  Future<String> getConfigPath() async {
    final appDir = await _getAppDirectory();
    return '$appDir/$configFileName';
  }
}
