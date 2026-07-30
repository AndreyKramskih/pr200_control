import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../models/modbus_data.dart';

import '../services/logger_service.dart';

class ModbusService extends ChangeNotifier {
  bool _connected = false;
  String _lastError = '';
  int _slaveId = 1;
  int _timeout = 3;
  String _ip = '';
  int _port = 502;
  final Map<int, int> _registerCache = {};
  final List<AlarmItem> _activeAlarms = [];

  static const int MAX_REGISTERS_PER_REQUEST = 12;

  bool get connected => _connected;
  String get lastError => _lastError;
  Map<int, int> get registerCache => _registerCache;
  List<AlarmItem> get activeAlarms => _activeAlarms;

  Future<bool> connect(
    String ip, {
    int port = 502,
    int slaveId = 1,
    int timeout = 3,
  }) async {
    LoggerService().log('🔵 Попытка подключения к $ip:$port, slaveId=$slaveId');

    try {
      _ip = ip;
      _port = port;
      _slaveId = slaveId;
      _timeout = timeout;

      final socket = await Socket.connect(
        ip,
        port,
        timeout: Duration(seconds: timeout),
      );
      socket.close();
      _connected = true;
      _lastError = '';
      LoggerService().log('✅ Подключение установлено');

      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      _connected = false;
      LoggerService().log('❌ Ошибка подключения: $e', level: LogLevel.error);
      notifyListeners();
      return false;
    }
  }

  void disconnect() {
    LoggerService().log('🔌 Отключение от устройства');
    _connected = false;
    _registerCache.clear();
    _activeAlarms.clear();
    notifyListeners();
    print('✅ disconnect: отключено');
  }

  Uint8List _buildModbusRequest(
    int functionCode,
    int address, {
    int count = 1,
    int? value,
    List<int>? values,
  }) {
    final byteBuffer = ByteData(512);
    final writer = byteBuffer.buffer.asByteData();

    int index = 0;

    writer.setUint16(index, Random().nextInt(65535));
    index += 2;

    writer.setUint16(index, 0);
    index += 2;

    final lengthPos = index;
    writer.setUint16(index, 0);
    index += 2;

    writer.setUint8(index, _slaveId);
    index += 1;

    writer.setUint8(index, functionCode);
    index += 1;

    if (functionCode == 3 || functionCode == 4) {
      writer.setUint16(index, address);
      index += 2;
      writer.setUint16(index, count);
      index += 2;
    } else if (functionCode == 6) {
      writer.setUint16(index, address);
      index += 2;
      writer.setUint16(index, value ?? 0);
      index += 2;
    } else if (functionCode == 16) {
      writer.setUint16(index, address);
      index += 2;
      writer.setUint16(index, count);
      index += 2;

      writer.setUint8(index, count * 2);
      index += 1;

      if (values != null && values.length == count) {
        for (int i = 0; i < count; i++) {
          writer.setUint16(index, values[i]);
          index += 2;
        }
      } else {
        for (int i = 0; i < count; i++) {
          writer.setUint16(index, 0);
          index += 2;
        }
      }
    } else {
      throw Exception('Unsupported function code: $functionCode');
    }

    final totalLength = index;
    writer.setUint16(lengthPos, totalLength - 6);
    return byteBuffer.buffer.asUint8List(0, totalLength);
  }

  Future<Uint8List?> _sendRequest(Uint8List request) async {
    Socket? tempSocket;

    try {
      print('📤 Отправка запроса...');

      tempSocket = await Socket.connect(
        _ip,
        _port,
        timeout: Duration(seconds: _timeout),
      );

      tempSocket.add(request);
      await tempSocket.flush();

      final completer = Completer<Uint8List>();
      final List<int> responseData = [];

      final subscription = tempSocket.listen(
        (data) {
          print('📥 Получено ${data.length} байт');
          responseData.addAll(data);

          if (responseData.length >= 8) {
            final length = (responseData[4] << 8) | responseData[5];
            if (responseData.length >= 6 + length) {
              if (!completer.isCompleted) {
                print('✅ Полный ответ получен (${responseData.length} байт)');
                completer.complete(Uint8List.fromList(responseData));
              }
            }
          }
        },
        onError: (e) {
          print('❌ Ошибка приема данных: $e');
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        },
        onDone: () {
          print('📭 Соединение закрыто');
          if (!completer.isCompleted) {
            completer.completeError(TimeoutException('Соединение закрыто'));
          }
        },
      );

      Timer? timer;
      if (_timeout > 0) {
        timer = Timer(Duration(seconds: _timeout), () {
          if (!completer.isCompleted) {
            print('⏰ Таймаут ${_timeout}с');
            completer.completeError(TimeoutException('Таймаут ${_timeout}с'));
          }
        });
      }

      try {
        final response = await completer.future;
        timer?.cancel();
        await subscription.cancel();
        await tempSocket.close();
        return response;
      } catch (e) {
        timer?.cancel();
        await subscription.cancel();
        await tempSocket.close();
        rethrow;
      }
    } on TimeoutException catch (e) {
      _lastError = e.toString();
      print('❌ _sendRequest: таймаут: $e');
      await tempSocket?.close();
      return null;
    } catch (e) {
      _lastError = e.toString();
      print('❌ _sendRequest: ошибка: $e');
      await tempSocket?.close();
      return null;
    }
  }

  Future<List<int>?> _readHoldingRegisters(int address, int count) async {
    print('🔵 _readHoldingRegisters: адрес=$address, кол-во=$count');

    try {
      final request = _buildModbusRequest(3, address, count: count);
      final response = await _sendRequest(request);

      if (response == null || response.length < 9) {
        print('❌ _readHoldingRegisters: пустой ответ или слишком короткий');
        return null;
      }

      final functionCode = response[7];
      if (functionCode != 3) {
        final errorCode = functionCode & 0x80;
        if (errorCode != 0) {
          _lastError = 'Ошибка Modbus: код ${response[8]}';
          print('❌ _readHoldingRegisters: ошибка Modbus, код ${response[8]}');
        } else {
          _lastError = 'Неожиданный код функции: $functionCode';
          print(
            '❌ _readHoldingRegisters: неожиданный код функции: $functionCode',
          );
        }
        return null;
      }

      final dataLength = response[8];
      final registers = <int>[];
      for (int i = 0; i < dataLength ~/ 2; i++) {
        final reg = (response[9 + i * 2] << 8) | response[10 + i * 2];
        registers.add(reg);
        print('📊 Регистр ${address + i} = $reg');
      }

      for (int i = 0; i < registers.length; i++) {
        _registerCache[address + i] = registers[i];
      }

      print('✅ _readHoldingRegisters: прочитано ${registers.length} регистров');
      return registers;
    } catch (e) {
      _lastError = e.toString();
      print('❌ _readHoldingRegisters: ошибка: $e');
      return null;
    }
  }

  // ==================== ГРУППОВОЕ ЧТЕНИЕ ====================

  Future<Map<int, int>> readMultipleRegisters(List<int> addresses) async {
    LoggerService().log('📖 Чтение ${addresses.length} регистров');

    if (!_connected || addresses.isEmpty) {
      return {};
    }

    final result = <int, int>{};

    final sortedAddresses = List<int>.from(addresses)..sort();

    final groups = <List<int>>[];
    var currentGroup = <int>[];

    for (final addr in sortedAddresses) {
      if (currentGroup.isEmpty) {
        currentGroup.add(addr);
      } else if (addr - currentGroup.last <= 1) {
        final start = currentGroup.first;
        final count = addr - start + 1;
        if (count <= MAX_REGISTERS_PER_REQUEST) {
          currentGroup.add(addr);
        } else {
          groups.add(List<int>.from(currentGroup));
          currentGroup = [addr];
        }
      } else {
        groups.add(List<int>.from(currentGroup));
        currentGroup = [addr];
      }
    }
    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }
    LoggerService().log('✅ Сформировано ${groups.length} групп для чтения');
    //print('🔵 Сформировано ${groups.length} групп для чтения');

    for (final group in groups) {
      final start = group.first;
      final end = group.last;
      final count = end - start + 1;

      LoggerService().log(
        '📖 Групповое чтение: адреса $start - $end (${count} регистров)',
      );
      //print('📖 Групповое чтение: адреса $start - $end (${count} регистров)');

      final registers = await _readHoldingRegisters(start, count);
      if (registers != null) {
        for (int i = 0; i < registers.length; i++) {
          final addr = start + i;
          if (addresses.contains(addr)) {
            result[addr] = registers[i];
          }
        }
      }
    }

    LoggerService().log(
      '✅ readMultipleRegisters: получено ${result.length} значений',
    );
    //print('✅ readMultipleRegisters: получено ${result.length} значений');
    return result;
  }

  Future<Map<int, double>> readMultipleFloats(List<int> addresses) async {
    LoggerService().log('🔵 readMultipleFloats: ${addresses.length} адресов');
    //print('🔵 readMultipleFloats: ${addresses.length} адресов');
    LoggerService().log('🔵 Адреса для чтения: $addresses');
    //print('   Адреса для чтения: $addresses');

    if (!_connected || addresses.isEmpty) {
      return {};
    }

    final result = <int, double>{};

    final sortedAddresses = List<int>.from(addresses)..sort();

    final groups = <List<int>>[];
    var currentGroup = <int>[];

    for (final addr in sortedAddresses) {
      if (currentGroup.isEmpty) {
        currentGroup.add(addr);
      } else {
        final lastAddr = currentGroup.last;
        // ✅ Float-адреса идут подряд, если разница = 1
        if (addr == lastAddr + 1) {
          final start = currentGroup.first;
          final newRegisterCount = ((addr - start) * 2) + 2;
          if (newRegisterCount <= MAX_REGISTERS_PER_REQUEST) {
            currentGroup.add(addr);
          } else {
            groups.add(List<int>.from(currentGroup));
            currentGroup = [addr];
          }
        } else {
          groups.add(List<int>.from(currentGroup));
          currentGroup = [addr];
        }
      }
    }
    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }

    print('🔵 Сформировано ${groups.length} групп для чтения float');

    for (final group in groups) {
      final start = group.first;
      final end = group.last;
      final registerCount = (end - start + 1) * 2;

      print(
        '📖 Групповое чтение float: start=$start, end=$end, регистров=$registerCount',
      );
      print('   Float адреса в группе: $group');

      final registers = await _readHoldingRegisters(start, registerCount);

      if (registers != null) {
        for (final addr in group) {
          final offset = (addr - start) * 2;
          if (offset + 1 < registers.length) {
            final loByte0 = registers[offset] & 0xFF;
            final loByte1 = (registers[offset] >> 8) & 0xFF;
            final hiByte2 = registers[offset + 1] & 0xFF;
            final hiByte3 = (registers[offset + 1] >> 8) & 0xFF;

            final bytes = Uint8List.fromList([
              loByte0,
              loByte1,
              hiByte2,
              hiByte3,
            ]);
            final byteData = ByteData.sublistView(bytes);
            final value = byteData.getFloat32(0, Endian.little);

            final roundedValue = double.parse(value.toStringAsFixed(1));
            result[addr] = roundedValue;
            print('✅ Адрес $addr = $roundedValue');
          }
        }
      }
    }

    print('✅ readMultipleFloats: получено ${result.length} значений');
    return result;
  }

  // ==================== ГРУППОВАЯ ЗАПИСЬ ====================

  Future<Map<int, bool>> writeMultipleRegisters(
    Map<int, dynamic> values, {
    String type = 'int',
  }) async {
    print('🔵 writeMultipleRegisters: ${values.length} параметров');

    if (!_connected || values.isEmpty) {
      return {};
    }

    final results = <int, bool>{};

    final intValues = <int, int>{};
    final floatValues = <int, double>{};

    for (final entry in values.entries) {
      if (type == 'float') {
        floatValues[entry.key] = double.parse(entry.value.toString());
      } else {
        intValues[entry.key] = int.parse(entry.value.toString());
      }
    }

    if (intValues.isNotEmpty) {
      final intResults = await _writeMultipleIntRegisters(intValues);
      results.addAll(intResults);
    }

    if (floatValues.isNotEmpty) {
      final floatResults = await _writeMultipleFloatRegisters(floatValues);
      results.addAll(floatResults);
    }

    print(
      '✅ writeMultipleRegisters: записано ${results.values.where((v) => v).length} из ${results.length}',
    );
    return results;
  }

  Future<Map<int, bool>> _writeMultipleIntRegisters(
    Map<int, int> values,
  ) async {
    final results = <int, bool>{};

    final sortedAddresses = values.keys.toList()..sort();

    final groups = <List<int>>[];
    var currentGroup = <int>[];

    for (final addr in sortedAddresses) {
      if (currentGroup.isEmpty) {
        currentGroup.add(addr);
      } else {
        final lastAddr = currentGroup.last;
        if (addr == lastAddr + 1) {
          final start = currentGroup.first;
          final count = addr - start + 1;
          if (count <= MAX_REGISTERS_PER_REQUEST) {
            currentGroup.add(addr);
          } else {
            groups.add(List<int>.from(currentGroup));
            currentGroup = [addr];
          }
        } else {
          groups.add(List<int>.from(currentGroup));
          currentGroup = [addr];
        }
      }
    }
    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }

    print('🔵 Сформировано ${groups.length} групп для записи int');

    for (final group in groups) {
      if (group.length == 1) {
        final addr = group.first;
        final success = await _writeSingleRegister(addr, values[addr] ?? 0);
        results[addr] = success;
        if (success) {
          _registerCache[addr] = values[addr] ?? 0;
        }
        print('📝 Одиночная запись адрес $addr: ${success ? "✅" : "❌"}');
        continue;
      }

      final start = group.first;
      final end = group.last;
      final count = end - start + 1;

      print(
        '📝 Групповая запись int: адреса $start - $end (${count} регистров)',
      );

      final valuesToWrite = <int>[];
      for (int i = 0; i < count; i++) {
        final addr = start + i;
        if (values.containsKey(addr)) {
          valuesToWrite.add(values[addr]!);
          print('   📝 Адрес $addr = ${values[addr]} (изменен)');
        } else {
          int currentValue = _registerCache[addr] ?? 0;
          if (!_registerCache.containsKey(addr)) {
            final readValue = await readRegister(addr);
            currentValue = readValue ?? 0;
          }
          valuesToWrite.add(currentValue);
          print('   📝 Адрес $addr = $currentValue (промежуточный)');
        }
      }

      final success = await _writeMultipleRegistersRaw(start, valuesToWrite);

      for (final addr in group) {
        results[addr] = success;
        if (success && values.containsKey(addr)) {
          _registerCache[addr] = values[addr]!;
        }
      }

      print('📝 Группа ${group.first}-${group.last}: ${success ? "✅" : "❌"}');
    }

    return results;
  }

  Future<Map<int, bool>> _writeMultipleFloatRegisters(
    Map<int, double> values,
  ) async {
    final results = <int, bool>{};

    final sortedAddresses = values.keys.toList()..sort();

    final groups = <List<int>>[];
    var currentGroup = <int>[];

    for (final addr in sortedAddresses) {
      if (currentGroup.isEmpty) {
        currentGroup.add(addr);
      } else {
        final lastAddr = currentGroup.last;
        // ✅ Float-адреса идут подряд, если разница = 1
        if (addr == lastAddr + 1) {
          final start = currentGroup.first;
          final newRegisterCount = ((addr - start) * 2) + 2;
          if (newRegisterCount <= MAX_REGISTERS_PER_REQUEST) {
            currentGroup.add(addr);
          } else {
            groups.add(List<int>.from(currentGroup));
            currentGroup = [addr];
          }
        } else {
          groups.add(List<int>.from(currentGroup));
          currentGroup = [addr];
        }
      }
    }
    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }

    print('🔵 Сформировано ${groups.length} групп для записи float');

    for (final group in groups) {
      if (group.length == 1) {
        final addr = group.first;
        final success = await writeFloat(addr, values[addr] ?? 0.0);
        results[addr] = success;
        if (success) {
          _registerCache[addr] = values[addr]?.toInt() ?? 0;
        }
        print('📝 Одиночная запись float адрес $addr: ${success ? "✅" : "❌"}');
      } else {
        final start = group.first;
        final floatValues = group.map((addr) => values[addr]!).toList();

        print(
          '📝 Групповая запись float: адреса ${group.first}-${group.last} (${floatValues.length} значений)',
        );

        final success = await _writeMultipleFloatsRaw(start, floatValues);

        for (final addr in group) {
          results[addr] = success;
          if (success) {
            _registerCache[addr] = values[addr]?.toInt() ?? 0;
          }
        }

        print('📝 Группа ${group.first}-${group.last}: ${success ? "✅" : "❌"}');
      }
    }

    return results;
  }

  Future<bool> _writeMultipleRegistersRaw(
    int startAddress,
    List<int> values,
  ) async {
    print(
      '🔵 _writeMultipleRegistersRaw: адрес=$startAddress, кол-во=${values.length}',
    );
    print('   Значения: $values');

    try {
      final request = _buildModbusRequest(
        16,
        startAddress,
        count: values.length,
        values: values,
      );
      final response = await _sendRequest(request);

      if (response == null || response.length < 8) {
        print('❌ _writeMultipleRegistersRaw: пустой ответ');
        return false;
      }

      if (response[7] != 16) {
        final errorCode = response[7] & 0x80;
        if (errorCode != 0) {
          _lastError = 'Ошибка Modbus: код ${response[8]}';
          print(
            '❌ _writeMultipleRegistersRaw: ошибка Modbus, код ${response[8]}',
          );
        }
        return false;
      }

      for (int i = 0; i < values.length; i++) {
        _registerCache[startAddress + i] = values[i];
      }

      print('✅ _writeMultipleRegistersRaw: запись успешна');
      return true;
    } catch (e) {
      _lastError = e.toString();
      print('❌ _writeMultipleRegistersRaw: ошибка: $e');
      return false;
    }
  }

  /// Групповая запись нескольких float-значений (если адреса идут подряд)
  /// Групповая запись нескольких float-значений (если адреса идут подряд)
  Future<bool> _writeMultipleFloatsRaw(
    int startAddress,
    List<double> values,
  ) async {
    print(
      '🔵 _writeMultipleFloatsRaw: адрес=$startAddress, кол-во=${values.length}',
    );

    final registers = <int>[];
    for (final floatValue in values) {
      final byteData = ByteData(4);
      byteData.setFloat32(0, floatValue, Endian.little);
      final bytes = byteData.buffer.asUint8List();

      final loReg = (bytes[1] << 8) | bytes[0];
      final hiReg = (bytes[3] << 8) | bytes[2];

      registers.add(loReg);
      registers.add(hiReg);
    }

    print('   Регистры для записи: $registers');
    return await _writeMultipleRegistersRaw(startAddress, registers);
  }

  Future<bool> _writeSingleRegister(int address, int value) async {
    print('🔵 _writeSingleRegister: адрес=$address, значение=$value');

    try {
      final request = _buildModbusRequest(6, address, value: value);
      final response = await _sendRequest(request);

      if (response == null || response.length < 8) {
        print('❌ _writeSingleRegister: пустой ответ');
        return false;
      }

      if (response[7] != 6) {
        final errorCode = response[7] & 0x80;
        if (errorCode != 0) {
          _lastError = 'Ошибка Modbus: код ${response[8]}';
          print('❌ _writeSingleRegister: ошибка Modbus, код ${response[8]}');
        }
        return false;
      }

      _registerCache[address] = value;
      print('✅ _writeSingleRegister: запись успешна');
      return true;
    } catch (e) {
      _lastError = e.toString();
      print('❌ _writeSingleRegister: ошибка: $e');
      return false;
    }
  }

  // ==================== ПУБЛИЧНЫЕ МЕТОДЫ ====================

  Future<int?> readRegister(
    int address, {
    int count = 1,
    String type = 'int',
  }) async {
    print('🔵 readRegister: адрес=$address, тип=$type');

    try {
      if (type == 'float') {
        final result = await readFloat(address);
        print('📊 readRegister float результат для $address: $result');
        return result?.toInt();
      }

      final registers = await _readHoldingRegisters(address, count);
      if (registers == null || registers.isEmpty) {
        print('❌ readRegister: не удалось прочитать регистр $address');
        return null;
      }

      print('📊 readRegister получены регистры для $address: $registers');

      if (type == 'bool') {
        final result = registers[0] & 0x01;
        print('📊 readRegister bool результат: $result');
        return result;
      }

      print('📊 readRegister int результат: ${registers[0]}');
      return registers[0];
    } catch (e) {
      print('❌ readRegister ошибка: $e');
      _lastError = e.toString();
      return null;
    }
  }

  Future<double?> readFloat(int address) async {
    print('🔵 readFloat: адрес=$address');

    try {
      print('📖 Читаю float с адреса $address');
      final registers = await _readHoldingRegisters(address, 2);
      if (registers == null || registers.length < 2) {
        print('❌ readFloat: не получены регистры для $address');
        return null;
      }

      print(
        '📊 Получены регистры: [${registers[0]}] (0x${registers[0].toRadixString(16)}), [${registers[1]}] (0x${registers[1].toRadixString(16)})',
      );

      final loByte0 = registers[0] & 0xFF;
      final loByte1 = (registers[0] >> 8) & 0xFF;
      final hiByte2 = registers[1] & 0xFF;
      final hiByte3 = (registers[1] >> 8) & 0xFF;

      final bytes = Uint8List.fromList([loByte0, loByte1, hiByte2, hiByte3]);
      final byteData = ByteData.sublistView(bytes);
      final value = byteData.getFloat32(0, Endian.little);

      final result = double.parse(value.toStringAsFixed(1));
      print('✅ Float значение для $address: $result');
      return result;
    } catch (e) {
      print('❌ Ошибка чтения float $address: $e');
      _lastError = e.toString();
      return null;
    }
  }

  Future<bool> writeRegister(
    int address,
    dynamic value, {
    String type = 'int',
  }) async {
    print('🔵 writeRegister: адрес=$address, значение=$value, тип=$type');

    try {
      if (type == 'float') {
        final floatValue = double.parse(value.toString());
        final byteData = ByteData(4);
        byteData.setFloat32(0, floatValue, Endian.little);
        final bytes = byteData.buffer.asUint8List();

        final loReg = (bytes[1] << 8) | bytes[0];
        final hiReg = (bytes[3] << 8) | bytes[2];

        print('🔵 writeRegister float: loReg=$loReg, hiReg=$hiReg');

        final success1 = await _writeSingleRegister(address, loReg);
        if (!success1) {
          print('❌ writeRegister: не удалось записать младший регистр');
          return false;
        }
        final success2 = await _writeSingleRegister(address + 1, hiReg);
        if (!success2) {
          print('❌ writeRegister: не удалось записать старший регистр');
          return false;
        }
        print('✅ writeRegister: float записан успешно');
        return success2;
      } else {
        final intValue = int.parse(value.toString());
        print('🔵 writeRegister int: запись $intValue в адрес $address');
        final result = await _writeSingleRegister(address, intValue);
        print('✅ writeRegister: результат записи = $result');
        return result;
      }
    } catch (e) {
      _lastError = e.toString();
      print('❌ writeRegister ошибка: $e');
      return false;
    }
  }

  Future<bool> writeFloat(int address, double value) async {
    return await writeRegister(address, value, type: 'float');
  }

  /// Запись ОДНОГО бита в регистр (без изменения других битов)
  Future<bool> writeBit(int address, int bit, int value) async {
    print('🔵 writeBit: адрес=$address, бит=$bit, значение=$value');

    if (!_connected) {
      _lastError = 'Нет подключения к ПЛК';
      return false;
    }

    try {
      final currentValue = await readRegister(address);
      if (currentValue == null) {
        print('❌ writeBit: не удалось прочитать регистр $address');
        return false;
      }

      print(
        '📊 Текущее значение регистра $address = $currentValue (0b${currentValue.toRadixString(2).padLeft(16, '0')})',
      );

      int newValue;
      if (value == 1) {
        newValue = currentValue | (1 << bit);
      } else {
        newValue = currentValue & ~(1 << bit);
      }

      print(
        '📊 Новое значение = $newValue (0b${newValue.toRadixString(2).padLeft(16, '0')})',
      );

      final result = await writeRegister(address, newValue);
      print('✅ writeBit: результат = $result');

      return result;
    } catch (e) {
      _lastError = e.toString();
      print('❌ writeBit ошибка: $e');
      return false;
    }
  }

  // ==================== АВАРИИ ====================

  Future<List<AlarmItem>> readAlarms(
    int address,
    List<AlarmConfig> alarms,
  ) async {
    LoggerService().log(
      '🔴 Проверка аварий (адрес: $address, кол-во: ${alarms.length})',
    );
    //print('🔵 readAlarms: адрес=$address, кол-во аварий=${alarms.length}');

    final activeAlarms = <AlarmItem>[];

    try {
      final value = await readRegister(address);
      if (value == null) {
        LoggerService().log(
          '❌ readAlarms: не удалось прочитать регистр $address',
          level: LogLevel.warning,
        );
        //print('❌ readAlarms: не удалось прочитать регистр $address');
        return [];
      }

      final binaryString = value.toRadixString(2).padLeft(16, '0');
      print('📊 readAlarms: регистр $address = $value (0b$binaryString)');

      for (final alarm in alarms) {
        final isActive = (value & (1 << alarm.bit)) != 0;
        print(
          '  🔍 Бит ${alarm.bit} (${alarm.name}): ${isActive ? "АКТИВЕН" : "не активен"}',
        );

        if (isActive) {
          LoggerService().log(
            '🔴 Обнаружено ${activeAlarms.length} активных аварий',
            level: LogLevel.warning,
          );
          //print('🔴 Авария: ${alarm.name} (бит ${alarm.bit}) активна');
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
      LoggerService().log('❌ readAlarms ошибка: $e', level: LogLevel.warning);
      //print('❌ readAlarms ошибка: $e');
      return [];
    }
  }

  // ==================== СБРОС АВАРИЙ ====================

  Future<bool> resetAlarms(int resetAddress, {int value = 1}) async {
    print('🔵 resetAlarms: адрес=$resetAddress, бит=14');

    if (!_connected) {
      _lastError = 'Нет подключения к ПЛК';
      LoggerService().log(
        '❌ resetAlarms: нет подключения',
        level: LogLevel.error,
      );
      //print('❌ resetAlarms: нет подключения');
      return false;
    }

    try {
      // 1. Читаем текущее значение регистра 513
      final currentValue = await readRegister(513);
      if (currentValue == null) {
        LoggerService().log(
          '❌ resetAlarms: не удалось прочитать регистр 513',
          level: LogLevel.error,
        );
        //print('❌ resetAlarms: не удалось прочитать регистр 513');
        return false;
      }

      print(
        '📊 Текущее значение регистра 513 = $currentValue (0b${currentValue.toRadixString(2).padLeft(16, '0')})',
      );

      // 2. Устанавливаем бит 14 (сброс аварий)
      int valueWithBit14 = currentValue | (1 << 14);
      print('📊 Устанавливаем бит 14: $valueWithBit14');

      bool success = await writeRegister(513, valueWithBit14);
      if (!success) {
        print('❌ resetAlarms: не удалось установить бит 14');
        return false;
      }

      // 3. Небольшая задержка
      await Future.delayed(Duration(milliseconds: 100));

      // 4. Снимаем бит 14 (возвращаем исходное значение)
      final afterWrite = await readRegister(513);
      if (afterWrite == null) {
        print('❌ resetAlarms: не удалось прочитать регистр после записи');
        return false;
      }

      int valueWithoutBit14 = afterWrite & ~(1 << 14);
      print('📊 Снимаем бит 14: $valueWithoutBit14');

      success = await writeRegister(513, valueWithoutBit14);
      print('✅ resetAlarms: результат = $success');

      return success;
    } catch (e) {
      _lastError = e.toString();
      print('❌ resetAlarms ошибка: $e');
      return false;
    }
  }

  Future<bool> ping() async {
    LoggerService().log('🔵 ping: проверка соединения');
    //print('🔵 ping: проверка соединения');
    final result = await _readHoldingRegisters(0, 1);
    LoggerService().log('✅ ping: результат = ${result != null}');
    //print('✅ ping: результат = ${result != null}');
    return result != null;
  }

  Future<dynamic> readParameterValue(ItemConfig param) async {
    print(
      '🔵 readParameterValue: ${param.name}, адрес=${param.address}, тип=${param.type}',
    );

    if (param.type == 'float') {
      final result = await readFloat(param.address);
      print('📊 readParameterValue: результат = $result');
      return result;
    } else {
      final result = await readRegister(
        param.address,
        count: 1,
        type: param.type,
      );
      print('📊 readParameterValue: результат = $result');
      return result;
    }
  }

  // ==================== ГЕТТЕРЫ ДЛЯ ДОСТУПА К ДАННЫМ ====================
  String get ip => _ip;
  int get port => _port;
  int get slaveId => _slaveId;
  int get timeout => _timeout;
}
