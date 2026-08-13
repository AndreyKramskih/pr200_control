// lib/services/modbus_manager.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/config_model.dart';
import '../models/modbus_data.dart';
import 'modbus_service.dart';
import 'modbus_rtu_service.dart';
import 'logger_service.dart';

/// Менеджер для работы с Modbus (автоматически выбирает TCP или RTU)
class ModbusManager {
  final BuildContext context;

  // ✅ Кеш
  final Map<int, CachedValue<int>> _intCache = {};
  final Map<int, CachedValue<double>> _floatCache = {};
  static const Duration CACHE_LIFETIME = Duration(seconds: 2);

  ModbusManager(this.context);

  // Определяем активный сервис для операций
  dynamic get _activeService {
    final modbus = Provider.of<ModbusService>(context, listen: false);
    final rtuService = Provider.of<ModbusRtuService>(context, listen: false);

    // Если RTU подключен - используем его
    if (rtuService.connected) {
      return rtuService;
    }
    // Иначе TCP
    return modbus;
  }

  bool get connected {
    final modbus = Provider.of<ModbusService>(context, listen: false);
    final rtuService = Provider.of<ModbusRtuService>(context, listen: false);
    return modbus.connected || rtuService.connected;
  }

  String get lastError {
    final modbus = Provider.of<ModbusService>(context, listen: false);
    final rtuService = Provider.of<ModbusRtuService>(context, listen: false);

    if (rtuService.connected && rtuService.lastError.isNotEmpty) {
      return rtuService.lastError;
    }
    if (modbus.connected && modbus.lastError.isNotEmpty) {
      return modbus.lastError;
    }
    return rtuService.lastError.isNotEmpty
        ? rtuService.lastError
        : modbus.lastError;
  }

  Map<int, int> get registerCache {
    final modbus = Provider.of<ModbusService>(context, listen: false);
    final rtuService = Provider.of<ModbusRtuService>(context, listen: false);

    if (rtuService.connected && rtuService.registerCache.isNotEmpty) {
      return rtuService.registerCache;
    }
    return modbus.registerCache;
  }

  // ==================== КЕШИРОВАНИЕ ====================

  bool _isCacheValid<T>(CachedValue<T>? cached) {
    if (cached == null) return false;
    return DateTime.now().difference(cached.timestamp) < CACHE_LIFETIME;
  }

  int? _getCachedInt(int address) {
    final cached = _intCache[address];
    if (_isCacheValid(cached)) {
      return cached!.value;
    }
    return null;
  }

  double? _getCachedFloat(int address) {
    final cached = _floatCache[address];
    if (_isCacheValid(cached)) {
      return cached!.value;
    }
    return null;
  }

  void _setCachedInt(int address, int value) {
    _intCache[address] = CachedValue(value, DateTime.now());
  }

  void _setCachedFloat(int address, double value) {
    _floatCache[address] = CachedValue(value, DateTime.now());
  }

  // ==================== ПУБЛИЧНЫЕ МЕТОДЫ ====================

  // Чтение регистра с кешем
  Future<int?> readRegister(
    int address, {
    int count = 1,
    String type = 'int',
    bool useCache = true,
  }) async {
    // Проверяем кеш
    if (useCache) {
      final cached = _getCachedInt(address);
      if (cached != null) {
        LoggerService().log(
          '📦 Кеш: адрес $address = $cached',
          level: LogLevel.debug,
        );
        return cached;
      }
    }

    final value = await _activeService.readRegister(
      address,
      count: count,
      type: type,
    );

    // Сохраняем в кеш
    if (value != null && type != 'float') {
      _setCachedInt(address, value);
    }

    return value;
  }

  // Чтение float с кешем
  Future<double?> readFloat(int address, {bool useCache = true}) async {
    // Проверяем кеш
    if (useCache) {
      final cached = _getCachedFloat(address);
      if (cached != null) {
        LoggerService().log(
          '📦 Кеш float: адрес $address = $cached',
          level: LogLevel.debug,
        );
        return cached;
      }
    }

    final value = await _activeService.readFloat(address);

    // Сохраняем в кеш
    if (value != null) {
      _setCachedFloat(address, value);
    }

    return value;
  }

  // Запись регистра (инвалидируем кеш)
  Future<bool> writeRegister(
    int address,
    dynamic value, {
    String type = 'int',
  }) async {
    final success = await _activeService.writeRegister(
      address,
      value,
      type: type,
    );

    // Инвалидируем кеш при успешной записи
    if (success) {
      _intCache.remove(address);
      _floatCache.remove(address);
    }

    return success;
  }

  // Запись бита (инвалидируем кеш)
  Future<bool> writeBit(int address, int bit, int value) async {
    final success = await _activeService.writeBit(address, bit, value);

    // Инвалидируем кеш при успешной записи
    if (success) {
      _intCache.remove(address);
      _floatCache.remove(address);
    }

    return success;
  }

  // Чтение нескольких регистров
  Future<Map<int, int>> readMultipleRegisters(
    List<int> addresses, {
    bool useCache = true,
  }) async {
    final result = <int, int>{};
    final List<int> addressesToRead = [];

    for (final address in addresses) {
      // Проверяем кеш
      if (useCache) {
        final cached = _getCachedInt(address);
        if (cached != null) {
          result[address] = cached;
          continue;
        }
      }
      addressesToRead.add(address);
    }

    // Читаем только то, чего нет в кеше
    if (addressesToRead.isNotEmpty) {
      final freshData = await _activeService.readMultipleRegisters(
        addressesToRead,
      );
      for (final entry in freshData.entries) {
        result[entry.key] = entry.value;
        _setCachedInt(entry.key, entry.value);
      }
    }

    return result;
  }

  // Чтение нескольких float
  Future<Map<int, double>> readMultipleFloats(
    List<int> addresses, {
    bool useCache = true,
  }) async {
    final result = <int, double>{};
    final List<int> addressesToRead = [];

    for (final address in addresses) {
      // Проверяем кеш
      if (useCache) {
        final cached = _getCachedFloat(address);
        if (cached != null) {
          result[address] = cached;
          continue;
        }
      }
      addressesToRead.add(address);
    }

    // Читаем только то, чего нет в кеше
    if (addressesToRead.isNotEmpty) {
      final freshData = await _activeService.readMultipleFloats(
        addressesToRead,
      );
      for (final entry in freshData.entries) {
        result[entry.key] = entry.value;
        _setCachedFloat(entry.key, entry.value);
      }
    }

    return result;
  }

  // Групповая запись (инвалидируем кеш)
  Future<bool> writeMultipleRegisters(
    Map<int, dynamic> values, {
    String type = 'int',
  }) async {
    final service = _activeService;

    final result = await service.writeMultipleRegisters(values, type: type);

    // Инвалидируем кеш для записанных адресов
    if (result is bool) {
      if (result) {
        for (final address in values.keys) {
          _intCache.remove(address);
          _floatCache.remove(address);
        }
      }
    } else if (result is Map<int, bool>) {
      for (final entry in result.entries) {
        if (entry.value) {
          _intCache.remove(entry.key);
          _floatCache.remove(entry.key);
        }
      }
    }

    if (result is Map<int, bool>) {
      return result.values.every((v) => v == true);
    }
    return result as bool;
  }

  // ==================== ОСТАЛЬНЫЕ МЕТОДЫ ====================

  // Аварии
  Future<List<AlarmItem>> readAlarms(
    int address,
    List<AlarmConfig> alarms,
  ) async {
    return await _activeService.readAlarms(address, alarms);
  }

  // Сброс аварий
  Future<bool> resetAlarms(int resetAddress, {int value = 1}) async {
    LoggerService().log('🔄 resetAlarms: адрес=$resetAddress, значение=$value');
    return await _activeService.resetAlarms(resetAddress, value: value);
  }

  // Чтение параметра
  Future<dynamic> readParameterValue(ItemConfig param) async {
    return await _activeService.readParameterValue(param);
  }

  // Пинг
  Future<bool> ping() async {
    return await _activeService.ping();
  }

  // Отключение
  Future<void> disconnect() async {
    final rtuService = Provider.of<ModbusRtuService>(context, listen: false);
    final modbus = Provider.of<ModbusService>(context, listen: false);

    if (rtuService.connected) {
      await rtuService.disconnect();
    }
    if (modbus.connected) {
      modbus.disconnect();
    }
  }

  // Очистка кеша
  void clearCache() {
    _intCache.clear();
    _floatCache.clear();
    LoggerService().log('🧹 Кеш очищен', level: LogLevel.debug);
  }

  // Инвалидация кеша для конкретного адреса
  void invalidateCache(int address) {
    _intCache.remove(address);
    _floatCache.remove(address);
  }
}

/// Кешированное значение
class CachedValue<T> {
  final T value;
  final DateTime timestamp;

  CachedValue(this.value, this.timestamp);

  @override
  String toString() => 'CachedValue($value, ${timestamp.toIso8601String()})';
}
