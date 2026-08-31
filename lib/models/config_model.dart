import 'package:flutter/material.dart';

class ConfigModel {
  final String projectName;
  final ModbusServer modbusServer;
  final Map<String, SystemConfig> systems;
  final ConnectionConfig connection;
  String connectionType; // ✅ 'tcp' или 'rtu'
  RtuConfig? rtuConfig; // ✅ Настройки RTU

  ConfigModel({
    required this.projectName,
    required this.modbusServer,
    required this.systems,
    required this.connection,
    this.connectionType = 'tcp', // ✅ По умолчанию TCP
    this.rtuConfig,
  });

  factory ConfigModel.fromJson(Map<String, dynamic> json) {
    return ConfigModel(
      projectName: json['project_name']?.toString() ?? 'ИТП №1',
      modbusServer: ModbusServer.fromJson(
        json['modbus_server'] as Map<String, dynamic>? ?? {},
      ),
      systems: _parseSystems(json['systems'] as Map<String, dynamic>?),
      connection: ConnectionConfig.fromJson(
        json['connection'] as Map<String, dynamic>? ?? {},
      ),
      connectionType: json['connection_type']?.toString() ?? 'tcp',
      rtuConfig: json['rtu_config'] != null
          ? RtuConfig.fromJson(json['rtu_config'] as Map<String, dynamic>)
          : null,
    );
  }

  static Map<String, SystemConfig> _parseSystems(
    Map<String, dynamic>? systemsJson,
  ) {
    if (systemsJson == null) return {};
    final result = <String, SystemConfig>{};
    systemsJson.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        result[key] = SystemConfig.fromJson(value);
      }
    });
    return result;
  }

  Map<String, dynamic> toJson() => {
    'project_name': projectName,
    'modbus_server': modbusServer.toJson(),
    'systems': systems.map((key, value) => MapEntry(key, value.toJson())),
    'connection': connection.toJson(),
    'connection_type': connectionType,
    if (rtuConfig != null) 'rtu_config': rtuConfig!.toJson(),
  };

  SystemConfig? getSystem(String id) => systems[id];

  SubmenuConfig? getSubmenu(String systemId, String submenuId) {
    final system = systems[systemId];
    return system?.submenus[submenuId];
  }
}

class ModbusServer {
  String ip;
  int port;
  int slaveId;
  int timeout;
  int retries;

  ModbusServer({
    this.ip = '192.168.1.100',
    this.port = 502,
    this.slaveId = 1,
    this.timeout = 3,
    this.retries = 3,
  });

  factory ModbusServer.fromJson(Map<String, dynamic> json) {
    return ModbusServer(
      ip: json['ip']?.toString() ?? '192.168.1.100',
      port: _toInt(json['port'], 502),
      slaveId: _toInt(json['slave_id'], 1),
      timeout: _toInt(json['timeout'], 3),
      retries: _toInt(json['retries'], 3),
    );
  }

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'port': port,
    'slave_id': slaveId,
    'timeout': timeout,
    'retries': retries,
  };

  static int _toInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }
}

class ConnectionConfig {
  final String name;
  final String icon;

  ConnectionConfig({
    this.name = 'Подключение к оборудованию',
    this.icon = '🔌',
  });

  factory ConnectionConfig.fromJson(Map<String, dynamic> json) {
    return ConnectionConfig(
      name: json['name']?.toString() ?? 'Подключение к оборудованию',
      icon: json['icon']?.toString() ?? '🔌',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'icon': icon};
}

class SystemConfig {
  final String name;
  final String icon;
  final Map<String, SubmenuConfig> submenus;

  SystemConfig({
    required this.name,
    required this.icon,
    required this.submenus,
  });

  factory SystemConfig.fromJson(Map<String, dynamic> json) {
    return SystemConfig(
      name: json['name']?.toString() ?? 'Система',
      icon: json['icon']?.toString() ?? '📁',
      submenus: _parseSubmenus(json['submenus'] as Map<String, dynamic>?),
    );
  }

  static Map<String, SubmenuConfig> _parseSubmenus(
    Map<String, dynamic>? submenusJson,
  ) {
    if (submenusJson == null) return {};
    final result = <String, SubmenuConfig>{};
    submenusJson.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        result[key] = SubmenuConfig.fromJson(value);
      }
    });
    return result;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'icon': icon,
    'submenus': submenus.map((key, value) => MapEntry(key, value.toJson())),
  };

  /// Найти первый бит (поле 'bit') в любом ItemConfig внутри подменю указанного типа.
  /// [type] — строка, например 'startstop', 'valve' и т.д.
  /// Возвращает null, если ничего не найдено.
  int? findFirstBitBySubmenuType(String type) {
    for (final submenu in submenus.values) {
      if (submenu.type == type && submenu.items != null) {
        for (final item in submenu.items!) {
          if (item.bit != null) return item.bit!;
        }
      }
    }
    return null;
  }

  /// Найти бит 'Режим работы' внутри подменю типа 'valve'.
  /// Возвращает null, если не найдено.
  int? findModeBitInValve() {
    for (final submenu in submenus.values) {
      if (submenu.type == 'valve' && submenu.items != null) {
        for (final item in submenu.items!) {
          if (item.name.contains('Режим работы') && item.bit != null) {
            return item.bit!;
          }
        }
      }
    }
    return null;
  }
}

class SubmenuConfig {
  final String name;
  final String icon;
  final String type;
  final List<ItemConfig>? items;
  final List<GroupConfig>? groups;
  final List<AlarmConfig>? alarms;
  final int? resetAddress;
  final int? resetBit;
  final List<ControlConfig>? controls;
  final bool? analog;

  SubmenuConfig({
    required this.name,
    required this.icon,
    required this.type,
    this.items,
    this.groups,
    this.alarms,
    this.resetAddress,
    this.resetBit,
    this.controls,
    this.analog,
  });

  factory SubmenuConfig.fromJson(Map<String, dynamic> json) {
    return SubmenuConfig(
      name: json['name']?.toString() ?? 'Подменю',
      icon: json['icon']?.toString() ?? '📄',
      type: json['type']?.toString() ?? 'monitoring',
      items: _parseItems(json['items'] as List<dynamic>?),
      groups: _parseGroups(json['groups'] as List<dynamic>?),
      alarms: _parseAlarms(json['alarms'] as List<dynamic>?),
      resetAddress: _toIntOrNull(json['reset_address']),
      resetBit: _toIntOrNull(json['reset_bit']),
      controls: _parseControls(json['controls'] as List<dynamic>?),
      analog: json['analog'] as bool?,
    );
  }

  static List<ItemConfig>? _parseItems(List<dynamic>? itemsJson) {
    if (itemsJson == null) return null;
    return itemsJson
        .whereType<Map<String, dynamic>>()
        .map((e) => ItemConfig.fromJson(e))
        .toList();
  }

  static List<GroupConfig>? _parseGroups(List<dynamic>? groupsJson) {
    if (groupsJson == null) return null;
    return groupsJson
        .whereType<Map<String, dynamic>>()
        .map((e) => GroupConfig.fromJson(e))
        .toList();
  }

  static List<AlarmConfig>? _parseAlarms(List<dynamic>? alarmsJson) {
    if (alarmsJson == null) return null;
    return alarmsJson
        .whereType<Map<String, dynamic>>()
        .map((e) => AlarmConfig.fromJson(e))
        .toList();
  }

  static List<ControlConfig>? _parseControls(List<dynamic>? controlsJson) {
    if (controlsJson == null) return null;
    return controlsJson
        .whereType<Map<String, dynamic>>()
        .map((e) => ControlConfig.fromJson(e))
        .toList();
  }

  static int? _toIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'icon': icon,
    'type': type,
    if (items != null) 'items': items!.map((e) => e.toJson()).toList(),
    if (groups != null) 'groups': groups!.map((e) => e.toJson()).toList(),
    if (alarms != null) 'alarms': alarms!.map((e) => e.toJson()).toList(),
    if (resetAddress != null) 'reset_address': resetAddress,
    if (resetBit != null) 'reset_bit': resetBit,
    if (controls != null) 'controls': controls!.map((e) => e.toJson()).toList(),
    if (analog != null) 'analog': analog,
  };

  bool get isSensors => type == 'sensors';
  bool get isRelays => type == 'relays';
  bool get isPumps => type == 'pumps';
  bool get isValve => type == 'valve';
  bool get isSettings => type == 'settings';
  bool get isAlarms => type == 'alarms';
  bool get isStartStop => type == 'startstop';
}

class ItemConfig {
  final String name;
  final int address;
  final int? bit;
  final String type;
  final String? unit;
  final List<String>? states;
  final int? min;
  final int? max;
  final dynamic defaultValue;
  final int? modeAddress;
  final List<String>? modeStates;
  final bool? isSetpoint;
  final String? icon;
  final bool? readonly;

  ItemConfig({
    required this.name,
    required this.address,
    this.bit,
    this.type = 'int',
    this.unit,
    this.states,
    this.min,
    this.max,
    this.defaultValue,
    this.modeAddress,
    this.modeStates,
    this.isSetpoint,
    this.icon,
    this.readonly,
  });

  factory ItemConfig.fromJson(Map<String, dynamic> json) {
    return ItemConfig(
      name: json['name']?.toString() ?? '',
      address: _toInt(json['address'], 0),
      bit: _toIntOrNull(json['bit']),
      type: json['type']?.toString() ?? 'int',
      unit: json['unit']?.toString(),
      states: _parseStates(json['states'] as List<dynamic>?),
      min: _toIntOrNull(json['min']),
      max: _toIntOrNull(json['max']),
      defaultValue: json['default'],
      modeAddress: _toIntOrNull(json['mode_address']),
      modeStates: _parseStates(json['mode_states'] as List<dynamic>?),
      isSetpoint: json['is_setpoint'] as bool?,
      icon: json['icon']?.toString(),
      readonly: json['readonly'] as bool?,
    );
  }

  static List<String>? _parseStates(List<dynamic>? statesJson) {
    if (statesJson == null) return null;
    return statesJson.map((e) => e.toString()).toList();
  }

  static int _toInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  static int? _toIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    if (bit != null) 'bit': bit,
    'type': type,
    if (unit != null) 'unit': unit,
    if (states != null) 'states': states,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (defaultValue != null) 'default': defaultValue,
    if (modeAddress != null) 'mode_address': modeAddress,
    if (modeStates != null) 'mode_states': modeStates,
    if (isSetpoint != null) 'is_setpoint': isSetpoint,
    if (icon != null) 'icon': icon,
    if (readonly != null) 'readonly': readonly,
  };

  String getStateText(dynamic value) {
    if (value == null) return '--';
    if (value is double) {
      return value.toStringAsFixed(1);
    }
    if (states != null && states!.isNotEmpty) {
      if (states!.length == 2) {
        final isOn = (value is int) && (value & (1 << (bit ?? 0))) != 0;
        return isOn ? states![1] : states![0];
      }
      return states![0];
    }
    if (bit != null && value is int) {
      return (value & (1 << bit!)) != 0 ? 'Вкл' : 'Выкл';
    }
    return value.toString();
  }

  Color getStateColor(dynamic value) {
    if (value == null) return Colors.grey;
    if (bit != null && value is int) {
      final isOn = (value & (1 << bit!)) != 0;
      return isOn ? Colors.green : Colors.red;
    }
    return Colors.black87;
  }

  bool isValidValue(dynamic value) {
    if (value == null) return false;
    if (min != null && max != null) {
      final numValue = _toNum(value);
      if (numValue != null) {
        return numValue >= min! && numValue <= max!;
      }
    }
    return true;
  }

  static num? _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }
}

class GroupConfig {
  final String name;
  final List<ItemConfig> items;

  GroupConfig({required this.name, required this.items});

  factory GroupConfig.fromJson(Map<String, dynamic> json) {
    return GroupConfig(
      name: json['name']?.toString() ?? 'Группа',
      items: _parseItems(json['items'] as List<dynamic>?),
    );
  }

  static List<ItemConfig> _parseItems(List<dynamic>? itemsJson) {
    if (itemsJson == null) return [];
    return itemsJson
        .whereType<Map<String, dynamic>>()
        .map((e) => ItemConfig.fromJson(e))
        .toList();
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'items': items.map((e) => e.toJson()).toList(),
  };
}

class AlarmConfig {
  final String name;
  final int address;
  final int bit;
  final String description;

  AlarmConfig({
    required this.name,
    required this.address,
    required this.bit,
    required this.description,
  });

  factory AlarmConfig.fromJson(Map<String, dynamic> json) {
    return AlarmConfig(
      name: json['name']?.toString() ?? 'Авария',
      address: _toInt(json['address'], 0),
      bit: _toInt(json['bit'], 0),
      description: json['description']?.toString() ?? '',
    );
  }

  static int _toInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'bit': bit,
    'description': description,
  };
}

class ControlConfig {
  final String name;
  final int address;
  final int value;
  final String type;

  ControlConfig({
    required this.name,
    required this.address,
    required this.value,
    this.type = 'int',
  });

  factory ControlConfig.fromJson(Map<String, dynamic> json) {
    return ControlConfig(
      name: json['name']?.toString() ?? '',
      address: _toInt(json['address'], 0),
      value: _toInt(json['value'], 0),
      type: json['type']?.toString() ?? 'int',
    );
  }

  static int _toInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'value': value,
    'type': type,
  };
}

// ✅ Добавляем класс RtuConfig в конец файла
class RtuConfig {
  int baudRate;
  int dataBits;
  int stopBits;
  String parity;
  String port; // ✅ ДОЛЖНО БЫТЬ это поле

  RtuConfig({
    this.baudRate = 9600,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 'none',
    required this.port, // ✅ ДОЛЖЕН БЫТЬ этот параметр
  });

  factory RtuConfig.fromJson(Map<String, dynamic> json) {
    return RtuConfig(
      port: json['port']?.toString() ?? '', // ✅ Читаем port из JSON
      baudRate: json['baud_rate'] as int? ?? 9600,
      dataBits: json['data_bits'] as int? ?? 8,
      stopBits: json['stop_bits'] as int? ?? 1,
      parity: json['parity']?.toString() ?? 'none',
    );
  }

  Map<String, dynamic> toJson() => {
    'baud_rate': baudRate,
    'data_bits': dataBits,
    'stop_bits': stopBits,
    'parity': parity,
  };
}
