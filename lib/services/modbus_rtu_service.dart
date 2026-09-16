// lib/services/modbus_rtu_service.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../models/modbus_data.dart';
import 'logger_service.dart';
import 'serial_port_abstraction.dart';
import 'package:synchronized/synchronized.dart';

/// Сервис Modbus RTU через USB (реальная реализация)
class ModbusRtuService extends ChangeNotifier {
  bool _connected = false;
  String _lastError = '';
  int _slaveId = 1;
  int _timeout = 3000;
  String _portName = '';
  int _baudRate = 9600;

  // ✅ Реентерабельная блокировка для последовательного выполнения операций
  final Lock _lock = Lock(reentrant: true);

  late final SerialPortAdapter _adapter = SerialPortFactory.create();
  StreamSubscription? _dataSub;
  StreamSubscription? _connSub;

  final Map<int, int> _registerCache = {};
  final Map<int, double> _floatCache = {};
  final List<AlarmItem> _activeAlarms = [];
  final List<int> _responseBuffer = [];

  bool get connected => _connected;
  String get lastError => _lastError;
  Map<int, int> get registerCache => _registerCache;
  Map<int, double> get floatCache => _floatCache;
  List<AlarmItem> get activeAlarms => _activeAlarms;
  String get portName => _portName;
  int get baudRate => _baudRate;
  int get slaveId => _slaveId;
  int get timeout => _timeout ~/ 1000;

  Future<List<SerialDeviceInfo>> getAvailableDevices() async {
    final devices = await _adapter.getAvailableDevices();
    LoggerService().log('🔍 Найдено устройств: ${devices.length}');
    return devices;
  }

  Future<List<String>> getAvailablePorts() async {
    final devices = await _adapter.getAvailableDevices();
    return devices.map((d) => d.deviceName).toList();
  }

  Future<bool> connect({
    required String port,
    int slaveId = 1,
    int timeout = 3,
    int baudRate = 9600,
  }) async {
    LoggerService().log('🔵 Подключение RTU: порт=$port, baudRate=$baudRate');
    try {
      _slaveId = slaveId;
      _timeout = timeout * 1000;
      _baudRate = baudRate;
      _portName = port;

      final devices = await _adapter.getAvailableDevices();
      if (devices.isEmpty) {
        _lastError = 'Устройства не найдены';
        LoggerService().log('❌ $_lastError', level: LogLevel.error);
        return false;
      }

      SerialDeviceInfo? target;
      for (final d in devices) {
        if (d.deviceName == port || d.deviceName.contains(port)) {
          target = d;
          break;
        }
      }
      target ??= devices.first;

      final ok = await _adapter.connect(target, baudRate);
      if (!ok) {
        _lastError = 'Не удалось подключиться к ${target.deviceName}';
        return false;
      }

      _connected = true;
      _lastError = '';
      _portName = target.deviceName;
      _startListening();

      LoggerService().log('✅ RTU подключен к ${target.deviceName}');
      notifyListeners();
      return true;
    } catch (e) {
      _connected = false;
      _lastError = e.toString();
      LoggerService().log(
        '❌ Ошибка подключения RTU: $e',
        level: LogLevel.error,
      );
      notifyListeners();
      return false;
    }
  }

  void _startListening() {
    _dataSub?.cancel();
    _connSub?.cancel();

    _dataSub = _adapter.dataStream.listen(
      (data) => _onDataReceived(data),
      onError: (e) =>
          LoggerService().log('❌ data stream: $e', level: LogLevel.error),
    );

    _connSub = _adapter.connectionStream.listen((isConnected) {
      _connected = isConnected;
      if (!isConnected) {
        LoggerService().log('🔌 Соединение потеряно');
        notifyListeners();
      }
    });
  }

  void _onDataReceived(List<int> data) {
    LoggerService().log(
      '📥 Получено ${data.length} байт: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}',
    );
    _responseBuffer.addAll(data);
  }

  Future<void> disconnect() async {
    LoggerService().log('🔌 Отключение RTU');
    _connected = false;
    _registerCache.clear();
    _floatCache.clear();
    _activeAlarms.clear();
    _responseBuffer.clear();

    await _dataSub?.cancel();
    await _connSub?.cancel();
    await _adapter.disconnect();

    notifyListeners();
  }

  Future<bool> ping() async {
    if (!_connected) {
      return false;
    }

    try {
      final Uint8List request = _buildModbusRequest(3, 0, 1);
      _responseBuffer.clear();

      final bool sent = await _adapter.write(request);
      if (!sent) {
        return false;
      }

      final Stopwatch stopwatch = Stopwatch()..start();
      while (stopwatch.elapsedMilliseconds < _timeout) {
        if (_responseBuffer.isNotEmpty) {
          final Uint8List response = Uint8List.fromList(_responseBuffer);
          _responseBuffer.clear();
          if (_verifyCrc(response)) {
            return true;
          }
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      return false;
    } catch (e) {
      LoggerService().log('⚠️ Ping failed: $e', level: LogLevel.warning);
      return false;
    }
  }

  // ==================== Modbus RTU протокол ====================

  int _crc16(List<int> data) {
    int crc = 0xFFFF;
    for (int b in data) {
      crc ^= b;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc >>= 1;
          crc ^= 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc;
  }

  bool _verifyCrc(Uint8List response) {
    if (response.length < 3) {
      return false;
    }

    final int receivedCrc =
        (response[response.length - 1] << 8) | response[response.length - 2];
    final int calculatedCrc = _crc16(response.sublist(0, response.length - 2));

    return receivedCrc == calculatedCrc;
  }

  Uint8List _buildModbusRequest(
    int functionCode,
    int address,
    int count, [
    int? value,
  ]) {
    final List<int> buffer = [];

    buffer.add(_slaveId);
    buffer.add(functionCode);

    if (functionCode == 3 || functionCode == 4) {
      buffer.add((address >> 8) & 0xFF);
      buffer.add(address & 0xFF);
      buffer.add((count >> 8) & 0xFF);
      buffer.add(count & 0xFF);
    } else if (functionCode == 6) {
      buffer.add((address >> 8) & 0xFF);
      buffer.add(address & 0xFF);
      buffer.add((value! >> 8) & 0xFF);
      buffer.add(value & 0xFF);
    } else if (functionCode == 16) {
      buffer.add((address >> 8) & 0xFF);
      buffer.add(address & 0xFF);
      buffer.add((count >> 8) & 0xFF);
      buffer.add(count & 0xFF);
      buffer.add(count * 2);
      for (int i = 0; i < count; i++) {
        buffer.add(0);
        buffer.add(0);
      }
    }

    final int crc = _crc16(buffer);
    buffer.add(crc & 0xFF);
    buffer.add((crc >> 8) & 0xFF);

    return Uint8List.fromList(buffer);
  }

  Future<Uint8List?> _sendModbusRequest(Uint8List request) async {
    if (!_connected) {
      _lastError = 'Нет подключения';
      return null;
    }

    try {
      LoggerService().log(
        '📤 RTU запрос: ${request.map((int e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );

      _responseBuffer.clear();

      final bool sent = await _adapter.write(request);
      if (!sent) {
        _lastError = 'Ошибка отправки запроса';
        return null;
      }

      // Определяем тип запроса (6 - запись одного регистра, 16 - групповая запись)
      final bool isWrite = request[1] == 6 || request[1] == 16;
      final Stopwatch stopwatch = Stopwatch()..start();

      while (stopwatch.elapsedMilliseconds < _timeout) {
        if (_responseBuffer.isNotEmpty) {
          final Uint8List response = Uint8List.fromList(_responseBuffer);
          _responseBuffer.clear();

          LoggerService().log(
            '📥 RTU ответ: ${response.map((int e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}',
          );

          if (!_verifyCrc(response)) {
            _lastError = 'CRC ошибка';
            return null;
          }

          if ((response[1] & 0x80) != 0) {
            _lastError = 'Modbus ошибка: ${response[2]}';
            LoggerService().log('❌ $_lastError', level: LogLevel.error);
            return null;
          }

          if (isWrite) {
            final bool validWriteResponse =
                response.length == 8 &&
                response[0] == request[0] &&
                response[1] == request[1] &&
                response[2] == request[2] &&
                response[3] == request[3] &&
                response[4] == request[4] &&
                response[5] == request[5];

            if (!validWriteResponse) {
              _lastError = 'Некорректный ответ на запись';
              LoggerService().log('❌ $_lastError', level: LogLevel.error);
              return null;
            }
          }

          return response;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      _lastError = 'Таймаут: нет ответа от устройства';
      LoggerService().log('❌ $_lastError', level: LogLevel.error);
      return null;
    } catch (e) {
      _responseBuffer.clear();
      _lastError = e.toString();
      LoggerService().log('❌ RTU ошибка: $e', level: LogLevel.error);
      return null;
    }
  }

  // ==================== Публичные методы ====================

  Future<int?> readRegister(
    int address, {
    int count = 1,
    String type = 'int',
  }) async {
    return await _lock.synchronized(() async {
      if (!_connected) {
        _lastError = 'Нет подключения';
        return null;
      }

      try {
        LoggerService().log('📖 RTU чтение: адрес=$address, тип=$type');

        final int regCount = type == 'float' ? 2 : count;
        final Uint8List request = _buildModbusRequest(3, address, regCount);
        final Uint8List? response = await _sendModbusRequest(request);

        if (response == null) {
          return null;
        }

        if (type == 'float') {
          if (response.length < 7) {
            return null;
          }
          final Uint8List bytes = Uint8List(4);
          bytes[0] = response[4];
          bytes[1] = response[3];
          bytes[2] = response[6];
          bytes[3] = response[5];

          final double floatValue = ByteData.sublistView(
            bytes,
          ).getFloat32(0, Endian.little);
          final double rounded = double.parse(floatValue.toStringAsFixed(1));
          _floatCache[address] = rounded;
          return rounded.toInt();
        } else {
          final int value = (response[3] << 8) | response[4];
          _registerCache[address] = value;
          LoggerService().log('📊 RTU регистр $address = $value');
          return value;
        }
      } catch (e) {
        _lastError = e.toString();
        LoggerService().log(
          '❌ RTU readRegister ошибка: $e',
          level: LogLevel.error,
        );
        return null;
      }
    });
  }

  Future<double?> readFloat(int address) async {
    return await _lock.synchronized(() async {
      if (!_connected) {
        _lastError = 'Нет подключения';
        return null;
      }

      try {
        LoggerService().log('📖 RTU readFloat: адрес=$address');

        final Uint8List request = _buildModbusRequest(3, address, 2);
        final Uint8List? response = await _sendModbusRequest(request);

        if (response == null || response.length < 7) {
          return null;
        }

        final Uint8List bytes = Uint8List(4);
        bytes[0] = response[4];
        bytes[1] = response[3];
        bytes[2] = response[6];
        bytes[3] = response[5];

        final double value = ByteData.sublistView(
          bytes,
        ).getFloat32(0, Endian.little);
        final double rounded = double.parse(value.toStringAsFixed(1));
        _floatCache[address] = rounded;

        LoggerService().log('📊 RTU float $address = $rounded');
        return rounded;
      } catch (e) {
        _lastError = e.toString();
        LoggerService().log(
          '❌ RTU readFloat ошибка: $e',
          level: LogLevel.error,
        );
        return null;
      }
    });
  }

  Future<bool> writeRegister(
    int address,
    num value, {
    String type = 'int',
  }) async {
    return await _lock.synchronized(() async {
      if (!_connected) {
        _lastError = 'Нет подключения';
        return false;
      }

      try {
        LoggerService().log(
          '📝 RTU запись: адрес=$address, значение=$value, тип=$type',
        );

        if (type == 'float') {
          final floatValue = value.toDouble();
          final ByteData byteData = ByteData(4);
          byteData.setFloat32(0, floatValue, Endian.little);
          final Uint8List bytes = byteData.buffer.asUint8List();

          final int loReg = (bytes[1] << 8) | bytes[0];
          final int hiReg = (bytes[3] << 8) | bytes[2];

          final bool success1 = await _writeSingleRegister(address, loReg);
          if (!success1) return false;

          final bool success2 = await _writeSingleRegister(address + 1, hiReg);
          if (!success2) return false;

          _floatCache[address] = floatValue;
          return true;
        } else {
          if (value % 1 != 0) {
            throw FormatException('Целочисленное значение ожидается');
          }
          return await _writeSingleRegister(address, value.toInt());
        }
      } catch (e) {
        _lastError = e.toString();
        LoggerService().log(
          '❌ RTU writeRegister ошибка: $e',
          level: LogLevel.error,
        );
        return false;
      }
    });
  }

  // Вспомогательный метод для записи одного регистра (НЕ обёрнут в блокировку,
  // так как вызывается только из writeRegister, который уже захватил блокировку)
  Future<bool> _writeSingleRegister(int address, int value) async {
    try {
      LoggerService().log(
        '🔵 _writeSingleRegister: адрес=$address, значение=$value',
        level: LogLevel.debug,
      );

      final request = _buildModbusRequest(6, address, 1, value);

      LoggerService().log(
        '📤 RTU запрос: ${request.map((int e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );

      _responseBuffer.clear();
      final bool sent = await _adapter.write(request);

      if (!sent) {
        _lastError = 'Ошибка отправки запроса';
        return false;
      }

      // Ждем ответ от устройства
      final Stopwatch stopwatch = Stopwatch()..start();
      bool hasResponse = false;
      Uint8List? response;

      while (stopwatch.elapsedMilliseconds < 800) {
        if (_responseBuffer.isNotEmpty) {
          response = Uint8List.fromList(_responseBuffer);
          _responseBuffer.clear();
          hasResponse = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 20));
      }

      if (hasResponse && response != null) {
        LoggerService().log(
          '📥 RTU ответ: ${response.map((int e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}',
        );

        final bool isExpectedResponse =
            response.length == 8 &&
            response[0] == _slaveId &&
            response[1] == 6 &&
            response[2] == (address >> 8) &&
            response[3] == (address & 0xFF) &&
            response[4] == (value >> 8) &&
            response[5] == (value & 0xFF);

        if (isExpectedResponse && _verifyCrc(response)) {
          _registerCache[address] = value;
          LoggerService().log(
            '✅ RTU запись подтверждена (адрес $address = $value)',
          );
          return true;
        }

        _lastError = 'Некорректный ответ на запись регистра';
        LoggerService().log('❌ $_lastError', level: LogLevel.error);
        return false;
      }

      _lastError = 'Таймаут: нет ответа на запись регистра';
      LoggerService().log('❌ $_lastError', level: LogLevel.error);
      return false;
    } catch (e) {
      _responseBuffer.clear();
      _lastError = e.toString();
      LoggerService().log(
        '❌ _writeSingleRegister ошибка: $e',
        level: LogLevel.error,
      );
      return false;
    }
  }

  Future<Map<int, int>> readMultipleRegisters(List<int> addresses) async {
    return await _lock.synchronized(() async {
      LoggerService().log('📖 RTU чтение ${addresses.length} регистров');

      if (!_connected || addresses.isEmpty) {
        return {};
      }

      final Map<int, int> result = {};
      final List<int> sortedAddresses = List<int>.from(addresses)..sort();

      // Группируем адреса
      final List<List<int>> groups = [];
      List<int> currentGroup = [];

      for (final int addr in sortedAddresses) {
        if (currentGroup.isEmpty) {
          currentGroup.add(addr);
        } else if (addr - currentGroup.last <= 1) {
          currentGroup.add(addr);
        } else {
          groups.add(currentGroup);
          currentGroup = [addr];
        }
      }
      if (currentGroup.isNotEmpty) {
        groups.add(currentGroup);
      }

      for (final List<int> group in groups) {
        if (group.length == 1) {
          final int? value = await readRegister(group.first);
          if (value != null) {
            result[group.first] = value;
          }
        } else {
          // Групповое чтение
          final int start = group.first;
          final int count = group.last - start + 1;
          try {
            final Uint8List request = _buildModbusRequest(3, start, count);
            final Uint8List? response = await _sendModbusRequest(request);

            if (response != null && response.length >= 5) {
              final int dataLength = response[2];
              for (int i = 0; i < dataLength ~/ 2; i++) {
                final int addr = start + i;
                final int value =
                    (response[3 + i * 2] << 8) | response[4 + i * 2];
                result[addr] = value;
                _registerCache[addr] = value;
              }
            }
          } catch (e) {
            // Если групповое чтение не удалось - читаем по одному
            for (final int addr in group) {
              final int? value = await readRegister(addr);
              if (value != null) {
                result[addr] = value;
              }
            }
          }
        }
      }

      LoggerService().log('✅ RTU прочитано ${result.length} регистров');
      return result;
    });
  }

  Future<Map<int, double>> readMultipleFloats(List<int> addresses) async {
    return await _lock.synchronized(() async {
      LoggerService().log('📖 RTU чтение ${addresses.length} float');

      if (!_connected || addresses.isEmpty) {
        return {};
      }

      final Map<int, double> result = {};

      for (final int addr in addresses) {
        final double? value = await readFloat(addr);
        if (value != null) {
          result[addr] = value;
        }
      }

      return result;
    });
  }

  Future<bool> writeMultipleRegisters(
    Map<int, num> values, {
    String type = 'int',
  }) async {
    return await _lock.synchronized(() async {
      LoggerService().log(
        '📝 RTU групповая запись: ${values.length} параметров',
      );

      if (!_connected || values.isEmpty) {
        return false;
      }

      bool allSuccess = true;

      for (final MapEntry<int, dynamic> entry in values.entries) {
        final bool success = await writeRegister(
          entry.key,
          entry.value,
          type: type,
        );
        if (!success) {
          allSuccess = false;
          LoggerService().log(
            '❌ Ошибка записи адреса ${entry.key}',
            level: LogLevel.error,
          );
        }
      }

      return allSuccess;
    });
  }

  Future<List<AlarmItem>> readAlarms(
    int address,
    List<AlarmConfig> alarms,
  ) async {
    return await _lock.synchronized(() async {
      LoggerService().log(
        '🔴 Проверка аварий (адрес: $address, кол-во: ${alarms.length})',
      );

      final List<AlarmItem> activeAlarms = [];

      try {
        final int? value = await readRegister(address);
        if (value == null) {
          return [];
        }

        for (final AlarmConfig alarm in alarms) {
          final bool isActive = (value & (1 << alarm.bit)) != 0;
          if (isActive) {
            LoggerService().log(
              '🔴 Авария: ${alarm.name} (бит ${alarm.bit}) активна',
              level: LogLevel.warning,
            );
            activeAlarms.add(
              AlarmItem(
                name: alarm.name,
                description: alarm.description,
                address: alarm.address,
                bit: alarm.bit,
              ),
            );
          }
        }

        return activeAlarms;
      } catch (e) {
        _lastError = e.toString();
        LoggerService().log(
          '❌ RTU readAlarms ошибка: $e',
          level: LogLevel.error,
        );
        return [];
      }
    });
  }

  Future<dynamic> readParameterValue(ItemConfig param) async {
    return await _lock.synchronized(() async {
      if (param.type == 'float') {
        return await readFloat(param.address);
      } else {
        return await readRegister(param.address, type: param.type);
      }
    });
  }
}
