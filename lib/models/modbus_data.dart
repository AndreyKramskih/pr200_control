import 'package:flutter/material.dart';

/// Модели данных для Modbus
/// Содержит классы для хранения результатов чтения Modbus регистров

class ModbusRegister {
  final int address;
  final int value;
  final DateTime timestamp;

  ModbusRegister({
    required this.address,
    required this.value,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'address': address,
    'value': value,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ModbusRegister.fromJson(Map<String, dynamic> json) {
    return ModbusRegister(
      address: json['address'] as int? ?? 0,
      value: json['value'] as int? ?? 0,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  @override
  String toString() => 'Register[$address] = $value';
}

/// Результат чтения нескольких регистров
class ModbusRegistersResult {
  final List<ModbusRegister> registers;
  final bool success;
  final String? error;

  ModbusRegistersResult({
    required this.registers,
    this.success = true,
    this.error,
  });

  factory ModbusRegistersResult.success(List<ModbusRegister> registers) {
    return ModbusRegistersResult(registers: registers);
  }

  factory ModbusRegistersResult.error(String error) {
    return ModbusRegistersResult(registers: [], success: false, error: error);
  }

  bool get hasError => !success;
  bool get hasData => registers.isNotEmpty;
  int get count => registers.length;

  @override
  String toString() => success
      ? '✅ RegistersResult: ${registers.length} регистров'
      : '❌ RegistersResult: $error';
}

/// Результат чтения одного регистра
class ModbusRegisterResult {
  final int? value;
  final bool success;
  final String? error;

  ModbusRegisterResult({this.value, this.success = true, this.error});

  factory ModbusRegisterResult.success(int value) {
    return ModbusRegisterResult(value: value);
  }

  factory ModbusRegisterResult.error(String error) {
    return ModbusRegisterResult(success: false, error: error);
  }

  bool get hasValue => value != null;
  bool get hasError => !success;

  @override
  String toString() =>
      success ? '✅ RegisterResult: $value' : '❌ RegisterResult: $error';
}

/// Результат чтения float значения
class ModbusFloatResult {
  final double? value;
  final bool success;
  final String? error;

  ModbusFloatResult({this.value, this.success = true, this.error});

  factory ModbusFloatResult.success(double value) {
    // Изменено: округление до 1 знака
    final rounded = double.parse(
      (value * 10).roundToDouble().toStringAsFixed(1),
    );
    return ModbusFloatResult(value: rounded);
  }

  factory ModbusFloatResult.error(String error) {
    return ModbusFloatResult(success: false, error: error);
  }

  bool get hasValue => value != null;
  bool get hasError => !success;
  String get formattedValue => value?.toStringAsFixed(1) ?? '--';

  @override
  String toString() =>
      success ? '✅ FloatResult: $value' : '❌ FloatResult: $error';
}

/// Результат чтения битового значения
class ModbusBitResult {
  final bool? value;
  final bool success;
  final String? error;

  ModbusBitResult({this.value, this.success = true, this.error});

  factory ModbusBitResult.success(bool value) {
    return ModbusBitResult(value: value);
  }

  factory ModbusBitResult.error(String error) {
    return ModbusBitResult(success: false, error: error);
  }

  bool get hasValue => value != null;
  bool get hasError => !success;
  String get stateText => value == true ? 'Вкл' : 'Выкл';
  Color get stateColor => value == true ? Colors.green : Colors.red;

  @override
  String toString() => success ? '✅ BitResult: $value' : '❌ BitResult: $error';
}

/// Данные датчика
class SensorData {
  final String name;
  final dynamic value;
  final String unit;
  final DateTime timestamp;
  final bool isError;
  final String? errorMessage;

  SensorData({
    required this.name,
    required this.value,
    required this.unit,
    DateTime? timestamp,
    this.isError = false,
    this.errorMessage,
  }) : timestamp = timestamp ?? DateTime.now();

  String get formattedValue => value?.toString() ?? '--';

  bool get hasValue => value != null;

  Color get valueColor {
    if (isError || value == null) return Colors.red;
    if (value is num) {
      final numValue = value as num;
      if (numValue < 0) return Colors.blue;
      if (numValue > 100) return Colors.orange;
      return Colors.green;
    }
    return Colors.black87;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'unit': unit,
    'timestamp': timestamp.toIso8601String(),
    'isError': isError,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      name: json['name']?.toString() ?? '',
      value: json['value'],
      unit: json['unit']?.toString() ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
      isError: json['isError'] as bool? ?? false,
      errorMessage: json['errorMessage']?.toString(),
    );
  }

  @override
  String toString() => 'Sensor: $name = $formattedValue $unit';
}

/// Данные реле
class RelayData {
  final String name;
  final bool isOn;
  final String? onText;
  final String? offText;
  final DateTime timestamp;

  RelayData({
    required this.name,
    required this.isOn,
    this.onText,
    this.offText,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get stateText => isOn ? (onText ?? 'Вкл') : (offText ?? 'Выкл');
  Color get stateColor => isOn ? Colors.green : Colors.red;
  IconData get stateIcon => isOn ? Icons.check_circle : Icons.cancel;

  Map<String, dynamic> toJson() => {
    'name': name,
    'isOn': isOn,
    'onText': onText,
    'offText': offText,
    'timestamp': timestamp.toIso8601String(),
  };

  factory RelayData.fromJson(Map<String, dynamic> json) {
    return RelayData(
      name: json['name']?.toString() ?? '',
      isOn: json['isOn'] as bool? ?? false,
      onText: json['onText']?.toString(),
      offText: json['offText']?.toString(),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  @override
  String toString() => 'Relay: $name = $stateText';
}

/// Данные насоса
class PumpData {
  final String name;
  final bool isOn;
  final String? onText;
  final String? offText;
  final DateTime timestamp;

  PumpData({
    required this.name,
    required this.isOn,
    this.onText,
    this.offText,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get stateText => isOn ? (onText ?? 'Вкл') : (offText ?? 'Выкл');
  Color get stateColor => isOn ? Colors.green : Colors.red;
  IconData get stateIcon => isOn ? Icons.play_arrow : Icons.stop;

  Map<String, dynamic> toJson() => {
    'name': name,
    'isOn': isOn,
    'onText': onText,
    'offText': offText,
    'timestamp': timestamp.toIso8601String(),
  };

  factory PumpData.fromJson(Map<String, dynamic> json) {
    return PumpData(
      name: json['name']?.toString() ?? '',
      isOn: json['isOn'] as bool? ?? false,
      onText: json['onText']?.toString(),
      offText: json['offText']?.toString(),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  @override
  String toString() => 'Pump: $name = $stateText';
}

/// Данные клапана
class ValveData {
  final int position; // 0-100
  final bool isOpening;
  final bool isClosing;
  final DateTime timestamp;

  ValveData({
    required this.position,
    this.isOpening = false,
    this.isClosing = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get positionText => '$position%';

  Color get positionColor {
    if (position < 20) return Colors.red;
    if (position < 50) return Colors.orange;
    return Colors.green;
  }

  String get statusText {
    if (isOpening) return 'Открывается';
    if (isClosing) return 'Закрывается';
    return 'Стоит';
  }

  Color get statusColor {
    if (isOpening) return Colors.blue;
    if (isClosing) return Colors.orange;
    return Colors.grey;
  }

  Map<String, dynamic> toJson() => {
    'position': position,
    'isOpening': isOpening,
    'isClosing': isClosing,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ValveData.fromJson(Map<String, dynamic> json) {
    return ValveData(
      position: json['position'] as int? ?? 0,
      isOpening: json['isOpening'] as bool? ?? false,
      isClosing: json['isClosing'] as bool? ?? false,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  @override
  String toString() => 'Valve: position = $position%, $statusText';
}

/// Данные аварии
class AlarmItem {
  final String name;
  final String description;
  final int address;
  final int bit;
  final DateTime timestamp;

  AlarmItem({
    required this.name,
    required this.description,
    required this.address,
    required this.bit,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get shortName =>
      name.length > 20 ? '${name.substring(0, 20)}...' : name;
  bool get isActive =>
      true; // Всегда активны, так как мы их только добавляем при наличии

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'address': address,
    'bit': bit,
    'timestamp': timestamp.toIso8601String(),
  };

  factory AlarmItem.fromJson(Map<String, dynamic> json) {
    return AlarmItem(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      address: json['address'] as int? ?? 0,
      bit: json['bit'] as int? ?? 0,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  @override
  String toString() => '🚨 $name: $description';
}

/// Состояние подключения
class ConnectionStateData {
  final bool isConnected;
  final String? ip;
  final int? port;
  final String? error;
  final DateTime timestamp;

  ConnectionStateData({
    this.isConnected = false,
    this.ip,
    this.port,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get statusText {
    if (isConnected) {
      return 'Подключено к $ip:$port';
    }
    return error ?? 'Не подключено';
  }

  Color get statusColor => isConnected ? Colors.green : Colors.red;
  IconData get statusIcon => isConnected ? Icons.wifi : Icons.wifi_off;

  String get connectionInfo {
    if (isConnected && ip != null && port != null) {
      return '$ip:$port';
    }
    return '--:--';
  }

  Map<String, dynamic> toJson() => {
    'isConnected': isConnected,
    'ip': ip,
    'port': port,
    'error': error,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ConnectionStateData.fromJson(Map<String, dynamic> json) {
    return ConnectionStateData(
      isConnected: json['isConnected'] as bool? ?? false,
      ip: json['ip']?.toString(),
      port: json['port'] as int?,
      error: json['error']?.toString(),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  @override
  String toString() => 'Connection: ${isConnected ? "✅" : "❌"} $statusText';
}
