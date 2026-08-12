// lib/services/modbus_manager.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/config_model.dart';
import '../models/modbus_data.dart';
import 'modbus_service.dart';
import 'modbus_rtu_service.dart';

/// Менеджер для работы с Modbus (автоматически выбирает TCP или RTU)
class ModbusManager {
  final BuildContext context;

  ModbusManager(this.context);

  // Определяем активный сервис для операций
  dynamic get _activeService {
    final modbus = Provider.of<ModbusService>(context, listen: false);
    final rtuService = Provider.of<ModbusRtuService>(context, listen: false);

    // ✅ Если RTU подключен - используем его
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

  // Чтение регистра
  Future<int?> readRegister(
    int address, {
    int count = 1,
    String type = 'int',
  }) async {
    return await _activeService.readRegister(address, count: count, type: type);
  }

  // Чтение float
  Future<double?> readFloat(int address) async {
    return await _activeService.readFloat(address);
  }

  // Запись регистра
  Future<bool> writeRegister(
    int address,
    dynamic value, {
    String type = 'int',
  }) async {
    return await _activeService.writeRegister(address, value, type: type);
  }

  // Запись бита
  Future<bool> writeBit(int address, int bit, int value) async {
    return await _activeService.writeBit(address, bit, value);
  }

  // Чтение нескольких регистров
  Future<Map<int, int>> readMultipleRegisters(List<int> addresses) async {
    return await _activeService.readMultipleRegisters(addresses);
  }

  // Чтение нескольких float
  Future<Map<int, double>> readMultipleFloats(List<int> addresses) async {
    return await _activeService.readMultipleFloats(addresses);
  }

  // Групповая запись
  Future<bool> writeMultipleRegisters(
    Map<int, dynamic> values, {
    String type = 'int',
  }) async {
    return await _activeService.writeMultipleRegisters(values, type: type);
  }

  // Аварии
  Future<List<AlarmItem>> readAlarms(
    int address,
    List<AlarmConfig> alarms,
  ) async {
    return await _activeService.readAlarms(address, alarms);
  }

  // Сброс аварий
  Future<bool> resetAlarms(int resetAddress, {int value = 1}) async {
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
}
