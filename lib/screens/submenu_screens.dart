// lib/screens/submenu_screens.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/config_model.dart';
import '../models/modbus_data.dart';
import '../services/modbus_manager.dart';
import '../services/logger_service.dart';
//import '../services/modbus_rtu_service.dart';
import '../widgets/sensors_list_widget.dart';
import '../widgets/relays_list_widget.dart';
import '../widgets/pumps_list_widget.dart';
import '../widgets/alarms_widget.dart';
import '../widgets/valve_widget.dart';
import '../widgets/start_stop_widget.dart';
import '../widgets/settings_widget.dart';

class SubmenuScreen extends StatefulWidget {
  final String systemId;
  final String submenuId;

  const SubmenuScreen({
    super.key,
    required this.systemId,
    required this.submenuId,
  });

  @override
  State<SubmenuScreen> createState() => _SubmenuScreenState();
}

class _SubmenuScreenState extends State<SubmenuScreen> {
  bool _isLoading = false;
  bool _isDropdownOpen = false;
  bool _isResettingAlarms = false;

  // Данные для реального времени (датчики, реле, статусы)
  final Map<String, dynamic> _realtimeData = {};

  // Данные для режимов насосов
  final Map<String, dynamic> _modeData = {};

  // Данные для настроек
  final Map<String, dynamic> _settingsData = {};

  final List<AlarmItem> _alarms = [];
  Timer? _updateTimer;

  bool get _isRealtimeType {
    final config = Provider.of<ConfigModel>(context, listen: false);
    final system = config.getSystem(widget.systemId);
    if (system == null) return false;
    final submenu = system.submenus[widget.submenuId];
    if (submenu == null) return false;

    const realtimeTypes = ['sensors', 'relays', 'pumps', 'valve', 'alarms'];
    return realtimeTypes.contains(submenu.type);
  }

  bool get _isSettingsType {
    final config = Provider.of<ConfigModel>(context, listen: false);
    final system = config.getSystem(widget.systemId);
    if (system == null) return false;
    final submenu = system.submenus[widget.submenuId];
    if (submenu == null) return false;
    return submenu.type == 'settings';
  }

  bool get _isPumpsType {
    final config = Provider.of<ConfigModel>(context, listen: false);
    final system = config.getSystem(widget.systemId);
    if (system == null) return false;
    final submenu = system.submenus[widget.submenuId];
    if (submenu == null) return false;
    return submenu.type == 'pumps';
  }

  @override
  void initState() {
    super.initState();
    _loadData();

    if (_isRealtimeType) {
      _startAutoUpdate();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  // ==================== УНИВЕРСАЛЬНЫЙ МЕТОД ДЛЯ ЗАПИСИ ====================
  Future<void> _performWrite(Future<void> Function() writeOperation) async {
    _updateTimer?.cancel();
    try {
      await writeOperation();
    } finally {
      // Возобновляем автообновление только если виджет активен и это realtime-тип
      if (mounted && _isRealtimeType) {
        _startAutoUpdate();
      }
    }
  }

  void _startAutoUpdate() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_isDropdownOpen || _isResettingAlarms) {
        return;
      }

      // Проверяем, не занят ли сервис (блокировка сама управляет очередью)
      // Больше не нужна проверка isWriting, просто пытаемся обновить
      if (!_isLoading) {
        _updateRealtimeData();
      }
    });
  }

  void _onDropdownOpen() {
    if (!mounted) return;
    if (!_isDropdownOpen) {
      setState(() {
        _isDropdownOpen = true;
      });
    }
  }

  void _onDropdownClose() {
    if (!mounted) return;
    if (_isDropdownOpen) {
      setState(() {
        _isDropdownOpen = false;
      });
    }
  }

  void _onModeChanged(int address, int newValue) {
    if (mounted) {
      setState(() {
        _modeData[address.toString()] = newValue;
      });
    }
  }

  // ==================== ЗАГРУЗКА ДАННЫХ ====================

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    final config = Provider.of<ConfigModel>(context, listen: false);
    final system = config.getSystem(widget.systemId);
    if (system == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final submenu = system.submenus[widget.submenuId];
    if (submenu == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    await _loadRealtimeData(submenu);

    if (_isSettingsType) {
      await _loadSettingsData(submenu);
    }

    if (_isPumpsType) {
      await _loadPumpModes(submenu);
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ==================== ЧТЕНИЕ РЕАЛЬНОГО ВРЕМЕНИ ====================

  Future<void> _loadRealtimeData(SubmenuConfig submenu) async {
    final modbusManager = ModbusManager(context);
    if (!modbusManager.connected) return;

    LoggerService().log('🔵 _loadRealtimeData: загрузка для ${submenu.name}');

    final Map<String, dynamic> newData = {};

    if (submenu.items != null && submenu.items!.isNotEmpty) {
      final intAddresses = <int>[];
      final floatAddresses = <int>[];

      for (final item in submenu.items!) {
        if (item.type == 'float') {
          floatAddresses.add(item.address);
        } else {
          intAddresses.add(item.address);
        }
      }

      if (intAddresses.isNotEmpty) {
        final intResults = await modbusManager.readMultipleRegisters(
          intAddresses,
        );
        for (final entry in intResults.entries) {
          newData['${entry.key}'] = entry.value;
        }
      }

      if (floatAddresses.isNotEmpty) {
        final floatResults = await modbusManager.readMultipleFloats(
          floatAddresses,
        );
        for (final entry in floatResults.entries) {
          newData['${entry.key}'] = entry.value;
        }
      }
    }

    if (mounted) {
      setState(() {
        _realtimeData.clear();
        _realtimeData.addAll(newData);
      });
      LoggerService().log(
        '✅ _loadRealtimeData: загружено ${_realtimeData.length} значений',
      );
    }

    // ЧТЕНИЕ АВАРИЙ
    if (submenu.type == 'alarms' &&
        submenu.alarms != null &&
        submenu.alarms!.isNotEmpty) {
      final alarmsByAddress = <int, List<AlarmConfig>>{};
      for (final alarm in submenu.alarms!) {
        alarmsByAddress.putIfAbsent(alarm.address, () => []).add(alarm);
      }

      final allActiveAlarms = <AlarmItem>[];

      for (final entry in alarmsByAddress.entries) {
        final address = entry.key;
        final alarmsForAddress = entry.value;

        try {
          final regValue = await modbusManager.readRegister(
            address,
            useCache: false,
          );

          if (regValue != null) {
            for (final alarm in alarmsForAddress) {
              final isActive = (regValue & (1 << alarm.bit)) != 0;
              if (isActive) {
                allActiveAlarms.add(
                  AlarmItem(
                    name: alarm.name,
                    description: alarm.description,
                    address: alarm.address,
                    bit: alarm.bit,
                  ),
                );
              }
            }
          }
        } catch (e) {
          LoggerService().log(
            '❌ Ошибка чтения регистра $address: $e',
            level: LogLevel.error,
          );
        }
      }

      if (mounted) {
        setState(() {
          _alarms.clear();
          _alarms.addAll(allActiveAlarms);
        });
        LoggerService().log(
          '🔴 Обнаружено ${allActiveAlarms.length} активных аварий',
          level: allActiveAlarms.isNotEmpty ? LogLevel.warning : LogLevel.info,
        );
      }
    }
  }

  Future<void> _updateRealtimeData() async {
    if (!mounted) return;

    if (_isDropdownOpen || _isResettingAlarms) {
      return;
    }

    // Проверка блокировки не нужна – она внутри сервиса

    final config = Provider.of<ConfigModel>(context, listen: false);
    final modbusManager = ModbusManager(context);

    if (!modbusManager.connected) return;

    final system = config.getSystem(widget.systemId);
    if (system == null) return;

    final submenu = system.submenus[widget.submenuId];
    if (submenu == null) return;

    final Map<String, dynamic> newData = {};

    if (submenu.items != null && submenu.items!.isNotEmpty) {
      final intAddresses = <int>[];
      final floatAddresses = <int>[];

      for (final item in submenu.items!) {
        if (item.type == 'float') {
          floatAddresses.add(item.address);
        } else {
          intAddresses.add(item.address);
        }
      }

      if (intAddresses.isNotEmpty) {
        final intResults = await modbusManager.readMultipleRegisters(
          intAddresses,
        );
        for (final entry in intResults.entries) {
          newData['${entry.key}'] = entry.value;
        }
      }

      if (floatAddresses.isNotEmpty) {
        final floatResults = await modbusManager.readMultipleFloats(
          floatAddresses,
        );
        for (final entry in floatResults.entries) {
          newData['${entry.key}'] = entry.value;
        }
      }
    }

    if (mounted) {
      bool hasChanges = false;
      if (_realtimeData.length != newData.length) {
        hasChanges = true;
      } else {
        for (final key in newData.keys) {
          if (_realtimeData[key] != newData[key]) {
            hasChanges = true;
            break;
          }
        }
      }

      if (hasChanges) {
        setState(() {
          _realtimeData.clear();
          _realtimeData.addAll(newData);
        });
      }
    }

    // Обновление аварий
    if (submenu.type == 'alarms' &&
        submenu.alarms != null &&
        submenu.alarms!.isNotEmpty) {
      final alarmsByAddress = <int, List<AlarmConfig>>{};
      for (final alarm in submenu.alarms!) {
        alarmsByAddress.putIfAbsent(alarm.address, () => []).add(alarm);
      }

      final allActiveAlarms = <AlarmItem>[];

      for (final entry in alarmsByAddress.entries) {
        final address = entry.key;
        final alarmsForAddress = entry.value;

        try {
          final regValue = await modbusManager.readRegister(
            address,
            useCache: false,
          );

          if (regValue != null) {
            for (final alarm in alarmsForAddress) {
              final isActive = (regValue & (1 << alarm.bit)) != 0;
              if (isActive) {
                allActiveAlarms.add(
                  AlarmItem(
                    name: alarm.name,
                    description: alarm.description,
                    address: alarm.address,
                    bit: alarm.bit,
                  ),
                );
              }
            }
          }
        } catch (e) {
          // Игнорируем ошибки при обновлении
        }
      }

      if (mounted) {
        bool alarmsChanged = false;
        if (_alarms.length != allActiveAlarms.length) {
          alarmsChanged = true;
        } else {
          final currentNames = _alarms.map((a) => a.name).toSet();
          final newNames = allActiveAlarms.map((a) => a.name).toSet();
          if (!currentNames.containsAll(newNames) ||
              !newNames.containsAll(currentNames)) {
            alarmsChanged = true;
          }
        }

        if (alarmsChanged) {
          setState(() {
            _alarms.clear();
            _alarms.addAll(allActiveAlarms);
          });
        }
      }
    }
  }

  // ==================== РЕЖИМЫ НАСОСОВ ====================

  Future<void> _loadPumpModes(SubmenuConfig submenu) async {
    final modbusManager = ModbusManager(context);
    if (!modbusManager.connected) return;

    if (submenu.items == null || submenu.items!.isEmpty) return;
    LoggerService().log('🔵 _loadPumpModes: загрузка режимов насосов...');

    final Map<String, dynamic> newModeData = {};
    bool hasChanges = false;

    for (final item in submenu.items!) {
      if (item.modeAddress != null) {
        final value = await modbusManager.readRegister(item.modeAddress!);
        LoggerService().log(
          '📊 Режим "${item.name}" (адрес ${item.modeAddress}) = $value',
        );

        if (value != null) {
          final key = item.modeAddress.toString();
          if (_modeData[key] != value) {
            hasChanges = true;
          }
          newModeData[key] = value;
        }
      }
    }
    LoggerService().log('📊 newModeData: $newModeData');

    if (hasChanges && mounted) {
      setState(() {
        _modeData.clear();
        _modeData.addAll(newModeData);
      });
      LoggerService().log(
        '✅ _loadPumpModes: режимы обновлены, _modeData = $_modeData',
      );
    }
  }

  // ==================== НАСТРОЙКИ ====================

  Future<void> _loadSettingsData(SubmenuConfig submenu) async {
    final modbusManager = ModbusManager(context);
    if (!modbusManager.connected) return;
    LoggerService().log('🔵 _loadSettingsData: загрузка настроек...');

    final Map<String, dynamic> newData = {};

    final intAddresses = <int>[];
    final floatAddresses = <int>[];
    final addressToItem = <int, ItemConfig>{};

    if (submenu.groups != null && submenu.groups!.isNotEmpty) {
      for (final group in submenu.groups!) {
        for (final item in group.items) {
          addressToItem[item.address] = item;
          if (item.type == 'float') {
            floatAddresses.add(item.address);
          } else {
            intAddresses.add(item.address);
          }
        }
      }
    }

    if (intAddresses.isNotEmpty) {
      final intResults = await modbusManager.readMultipleRegisters(
        intAddresses,
      );
      for (final entry in intResults.entries) {
        final item = addressToItem[entry.key];
        if (item != null) {
          LoggerService().log('✅ ${item.name} = ${entry.value}');
          newData['${entry.key}'] = entry.value;
        }
      }
    }

    if (floatAddresses.isNotEmpty) {
      final floatResults = await modbusManager.readMultipleFloats(
        floatAddresses,
      );
      for (final entry in floatResults.entries) {
        final item = addressToItem[entry.key];
        if (item != null) {
          LoggerService().log('✅ ${item.name} = ${entry.value}');
          newData['${entry.key}'] = entry.value;
        }
      }
    }

    for (final item in addressToItem.values) {
      final key = '${item.address}';
      if (!newData.containsKey(key)) {
        LoggerService().log(
          '⚠️ ${item.name} не прочитан, использую default: ${item.defaultValue}',
        );
        newData[key] = item.defaultValue;
      }
    }

    if (mounted) {
      setState(() {
        _settingsData.clear();
        _settingsData.addAll(newData);
      });
      LoggerService().log(
        '✅ _loadSettingsData: загружено ${_settingsData.length} значений',
      );
    }
  }

  // ==================== ОБНОВЛЕНИЕ НАСТРОЕК ====================

  Future<void> _reloadSettings() async {
    if (!mounted) return;

    final config = Provider.of<ConfigModel>(context, listen: false);
    final system = config.getSystem(widget.systemId);
    if (system == null) return;

    final submenu = system.submenus[widget.submenuId];
    if (submenu == null) return;

    await _loadSettingsData(submenu);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Настройки обновлены с контроллера'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // ==================== РУЧНОЕ ОБНОВЛЕНИЕ ====================

  Future<void> _manualRefresh() async {
    if (!mounted) return;

    final config = Provider.of<ConfigModel>(context, listen: false);
    final system = config.getSystem(widget.systemId);
    if (system == null) return;

    final submenu = system.submenus[widget.submenuId];
    if (submenu == null) return;

    await _loadRealtimeData(submenu);

    if (_isSettingsType) {
      await _loadSettingsData(submenu);
    }

    if (_isPumpsType) {
      await _loadPumpModes(submenu);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Данные обновлены'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // ==================== СОХРАНЕНИЕ НАСТРОЕК ====================

  Future<void> _saveAllSettings() async {
    await _performWrite(() async {
      final modbusManager = ModbusManager(context);
      final config = Provider.of<ConfigModel>(context, listen: false);

      if (!modbusManager.connected) {
        _showError('Нет подключения к ПЛК');
        return;
      }

      final system = config.getSystem(widget.systemId);
      if (system == null) return;

      final submenu = system.submenus[widget.submenuId];
      if (submenu == null) return;

      final Map<int, dynamic> changedValues = <int, dynamic>{};

      if (submenu.groups != null && submenu.groups!.isNotEmpty) {
        for (final group in submenu.groups!) {
          for (final item in group.items) {
            final key = '${item.address}';
            final newValue = _settingsData[key];
            if (newValue != null) {
              dynamic currentValue;
              if (item.type == 'float') {
                currentValue = await modbusManager.readFloat(item.address);
              } else {
                currentValue = await modbusManager.readRegister(
                  item.address,
                  type: item.type,
                );
              }

              if (currentValue != null && newValue != currentValue) {
                changedValues[item.address] = newValue;
              }
            }
          }
        }
      }

      if (changedValues.isEmpty) {
        _showSuccess('Нет измененных параметров для сохранения');
        return;
      }
      LoggerService().log(
        '🔵 Сохранение ${changedValues.length} измененных параметров...)',
      );

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Сохранить параметры?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Будет сохранено ${changedValues.length} параметров:'),
              const SizedBox(height: 8),
              ...changedValues.keys.take(10).map((addr) {
                final item = _findItemByAddress(submenu, addr);
                final value = changedValues[addr];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${item?.name ?? 'Адрес $addr'}: $value',
                    style: const TextStyle(fontSize: 14),
                  ),
                );
              }).toList(),
              if (changedValues.length > 10)
                Text('... и еще ${changedValues.length - 10} параметров'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      );

      if (confirm != true || !mounted) return;

      final intValues = <int, int>{};
      final floatValues = <int, double>{};

      for (final entry in changedValues.entries) {
        final item = _findItemByAddress(submenu, entry.key);
        if (item != null) {
          if (item.type == 'float') {
            floatValues[entry.key] = double.parse(entry.value.toString());
          } else {
            intValues[entry.key] = int.parse(entry.value.toString());
          }
        }
      }

      bool allSuccess = true;

      if (intValues.isNotEmpty) {
        final success = await modbusManager.writeMultipleRegisters(
          intValues,
          type: 'int',
        );
        if (!success) allSuccess = false;
      }

      if (floatValues.isNotEmpty) {
        final success = await modbusManager.writeMultipleRegisters(
          floatValues,
          type: 'float',
        );
        if (!success) allSuccess = false;
      }

      if (mounted) {
        if (allSuccess) {
          _showSuccess('Все параметры сохранены!');
          await _reloadSettings();
        } else {
          _showError('Ошибка при сохранении некоторых параметров');
          await _reloadSettings();
        }
      }
    });
  }

  ItemConfig? _findItemByAddress(SubmenuConfig submenu, int address) {
    if (submenu.groups != null) {
      for (final group in submenu.groups!) {
        for (final item in group.items) {
          if (item.address == address) {
            return item;
          }
        }
      }
    }
    return null;
  }

  // ==================== КЛАПАН ====================

  Future<void> _switchValveMode() async {
    await _performWrite(() async {
      if (!mounted) return;

      final config = Provider.of<ConfigModel>(context, listen: false);
      final system = config.getSystem(widget.systemId);
      if (system == null) return;
      final submenu = system.submenus[widget.submenuId];
      if (submenu == null) return;

      ItemConfig? modeItem;
      if (submenu.items != null) {
        for (final item in submenu.items!) {
          if (item.name.contains('Режим работы')) {
            modeItem = item;
            break;
          }
        }
      }
      if (modeItem == null) return;

      final modbusManager = ModbusManager(context);

      try {
        final currentValue = await modbusManager.readRegister(modeItem.address);
        if (currentValue == null) {
          if (mounted) _showError('Не удалось прочитать текущий режим');
          return;
        }

        final isManual = (currentValue & (1 << (modeItem.bit ?? 0))) != 0;
        final newValue = isManual
            ? currentValue & ~(1 << (modeItem.bit ?? 0))
            : currentValue | (1 << (modeItem.bit ?? 0));

        final success = await modbusManager.writeRegister(
          modeItem.address,
          newValue,
        );

        if (success && mounted) {
          _showSuccess(
            isManual
                ? 'Режим переключен на АВТО'
                : 'Режим переключен на РУЧНОЙ',
          );
          await _loadRealtimeData(submenu);
        } else if (mounted) {
          _showError('Не удалось переключить режим');
        }
      } catch (e) {
        LoggerService().log(
          '❌ Ошибка переключения режима клапана: $e',
          level: LogLevel.error,
        );
        if (mounted) _showError('Ошибка: $e');
      }
    });
  }

  Future<void> _sendValveCommand(int address, int value) async {
    await _performWrite(() async {
      if (!mounted) return;

      final modbusManager = ModbusManager(context);
      final success = await modbusManager.writeRegister(address, value);
      if (mounted) {
        if (success) {
          _showSuccess('Команда отправлена');
          await _updateRealtimeData();
        } else {
          _showError('Ошибка отправки команды');
        }
      }
    });
  }

  void _onSetSetpoint(int address, dynamic value) {
    if (mounted) {
      setState(() {
        _settingsData[address.toString()] = value;
      });
    }
  }

  // ==================== АВАРИИ ====================

  Future<void> _resetAlarms() async {
    if (!mounted) return;

    final config = Provider.of<ConfigModel>(context, listen: false);
    final system = config.getSystem(widget.systemId);
    if (system == null) return;
    final submenu = system.submenus[widget.submenuId];
    if (submenu == null) return;
    if (submenu.resetAddress == null) return;

    final resetAddress = submenu.resetAddress!;
    final resetBit = submenu.resetBit ?? 3;

    // Поиск битов Start/Stop и Mode
    int? startStopBit;
    int? modeBit;

    for (final entry in system.submenus.entries) {
      if (entry.value.type == 'startstop' && entry.value.items != null) {
        for (final item in entry.value.items!) {
          if (item.bit != null) {
            startStopBit = item.bit!;
            break;
          }
        }
      }
      if (startStopBit != null) break;
    }

    for (final entry in system.submenus.entries) {
      if (entry.value.type == 'valve' && entry.value.items != null) {
        for (final item in entry.value.items!) {
          if (item.name.contains('Режим работы') && item.bit != null) {
            modeBit = item.bit!;
            break;
          }
        }
      }
      if (modeBit != null) break;
    }

    LoggerService().log(
      '🔍 Найден Start/Stop бит: ${startStopBit ?? "не найден"}',
    );
    LoggerService().log('🔍 Найден Mode бит: ${modeBit ?? "не найден"}');

    final modbusManager = ModbusManager(context);

    if (!modbusManager.connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет подключения к контроллеру'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сброс аварий'),
        content: const Text(
          'Вы уверены, что хотите сбросить все активные аварии?\n\n'
          '⚠️ Сброс возможен только если причина аварии устранена.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isResettingAlarms = true;
      _isLoading = true;
    });

    try {
      LoggerService().log(
        '🔄 Сброс аварий: адрес=$resetAddress, бит=$resetBit',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⏳ Сброс аварий...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // ✅ ВЫЗЫВАЕМ НОВЫЙ УНИВЕРСАЛЬНЫЙ МЕТОД
      final success = await modbusManager.resetAlarms(
        resetAddress: resetAddress,
        resetBit: resetBit,
        controlAddress: resetAddress, // обычно тот же адрес
        startStopBit:
            startStopBit ??
            0, // если не найден — передаём 0 (но лучше обработать)
        modeBit: modeBit ?? 1,
      );

      if (success) {
        // Обновляем данные после сброса
        await _loadRealtimeData(submenu);

        if (mounted) {
          if (_alarms.isEmpty) {
            _showSuccess('✅ Все аварии сброшены!');
          } else {
            _showWarning(
              '⚠️ Остались активные аварии: ${_alarms.map((a) => a.name).join(", ")}\n'
              'Устраните причину и повторите сброс.',
            );
          }
        }
      } else {
        // Ошибка — показываем сообщение из менеджера
        if (mounted) {
          _showError('Ошибка сброса аварий: ${modbusManager.lastError}');
        }
      }
    } catch (e) {
      LoggerService().log('❌ Ошибка сброса аварий: $e', level: LogLevel.error);
      if (mounted) _showError('Ошибка сброса аварий: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isResettingAlarms = false;
          _isLoading = false;
        });
      }
    }
  }
  // ==================== СТАРТ/СТОП ====================

  Future<void> _toggleStartStop() async {
    await _performWrite(() async {
      if (!mounted) return;

      final config = Provider.of<ConfigModel>(context, listen: false);
      final system = config.getSystem(widget.systemId);
      if (system == null) return;
      final submenu = system.submenus[widget.submenuId];
      if (submenu == null) return;
      if (submenu.items == null || submenu.items!.isEmpty) return;

      final item = submenu.items!.first;
      final currentValue = _realtimeData[item.address.toString()] ?? 0;
      final isOn = (currentValue & (1 << (item.bit ?? 0))) != 0;

      final newRegister = isOn
          ? currentValue & ~(1 << (item.bit ?? 0))
          : currentValue | (1 << (item.bit ?? 0));

      final modbusManager = ModbusManager(context);

      try {
        final success = await modbusManager.writeRegister(
          item.address,
          newRegister,
        );

        if (mounted) {
          if (success) {
            _showSuccess(isOn ? 'Выключено' : 'Включено');
            await _loadRealtimeData(submenu);
          } else {
            _showError('Ошибка изменения состояния');
          }
        }
      } catch (e) {
        LoggerService().log('❌ Ошибка старт/стоп: $e', level: LogLevel.error);
        if (mounted) _showError('Ошибка: $e');
      }
    });
  }

  // ==================== ПАРАМЕТРЫ (НАСТРОЙКИ) ====================

  void _onParamChanged(ItemConfig item, dynamic newValue) {
    if (mounted) {
      setState(() {
        _settingsData[item.address.toString()] = newValue;
      });
    }
  }

  Future<void> _onParamSave(ItemConfig item, dynamic newValue) async {
    await _performWrite(() async {
      if (!mounted) return;

      final modbusManager = ModbusManager(context);
      LoggerService().log(
        '🔵 Сохранение: ${item.name} = $newValue в адрес ${item.address}',
      );

      final success = await modbusManager.writeRegister(
        item.address,
        newValue,
        type: item.type,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Параметр сохранен' : 'Ошибка сохранения'),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      if (success && mounted) {
        await _reloadSettings();
      }
    });
  }

  Future<dynamic> _onParamLoad(ItemConfig item) async {
    if (!mounted) return null;

    final modbusManager = ModbusManager(context);
    dynamic loadedValue;
    if (item.type == 'float') {
      loadedValue = await modbusManager.readFloat(item.address);
    } else {
      loadedValue = await modbusManager.readRegister(
        item.address,
        type: item.type,
      );
    }
    if (loadedValue != null && mounted) {
      setState(() {
        _settingsData[item.address.toString()] = loadedValue;
      });
    }
    return loadedValue;
  }

  // ==================== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ====================

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showWarning(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final config = Provider.of<ConfigModel>(context);
    final system = config.getSystem(widget.systemId);

    if (system == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ошибка'),
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: Text('Система не найдена')),
      );
    }

    final submenu = system.submenus[widget.submenuId];
    if (submenu == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ошибка'),
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: Text('Подменю не найдено')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${submenu.icon} ${submenu.name}'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _manualRefresh,
            tooltip: 'Обновить',
          ),
          if (_isRealtimeType)
            const IconButton(
              icon: Icon(Icons.timer, color: Colors.green),
              onPressed: null,
              tooltip: 'Автообновление активно',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _manualRefresh,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: Theme.of(context).brightness == Brightness.dark
                  ? [Colors.grey[900]!, Colors.grey[800]!]
                  : [Colors.grey[50]!, Colors.grey[200]!],
            ),
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(submenu),
        ),
      ),
    );
  }

  Widget _buildContent(SubmenuConfig submenu) {
    switch (submenu.type) {
      case 'sensors':
        return SensorsListWidget(submenu: submenu, realtimeData: _realtimeData);
      case 'relays':
        return RelaysListWidget(submenu: submenu, realtimeData: _realtimeData);
      case 'pumps':
        return PumpsListWidget(
          submenu: submenu,
          realtimeData: _realtimeData,
          modeData: _modeData,
          onDropdownOpen: _onDropdownOpen,
          onDropdownClose: _onDropdownClose,
          onModeChanged: _onModeChanged,
          onModeWrite: _handlePumpModeWrite, // новый колбэк
        );
      case 'valve':
        return ValveWidget(
          submenu: submenu,
          realtimeData: _realtimeData,
          settingsData: _settingsData,
          onSwitchMode: _switchValveMode,
          onSendCommand: _sendValveCommand,
          onSetSetpoint: _onSetSetpoint,
        );
      case 'settings':
        return SettingsWidget(
          submenu: submenu,
          settingsData: _settingsData,
          onReloadSettings: _reloadSettings,
          onSaveAllSettings: _saveAllSettings,
          onParamChanged: _onParamChanged,
          onParamSave: _onParamSave,
          onParamLoad: _onParamLoad,
        );
      case 'alarms':
        return AlarmsWidget(
          submenu: submenu,
          alarms: _alarms,
          onResetAlarms: _resetAlarms,
          isResetting: _isResettingAlarms,
        );
      case 'startstop':
        return StartStopWidget(
          submenu: submenu,
          realtimeData: _realtimeData,
          onToggle: _toggleStartStop,
        );
      default:
        return const Center(child: Text('Неизвестный тип подменю'));
    }
  }

  // ==================== НОВЫЙ МЕТОД ДЛЯ ЗАПИСИ РЕЖИМА НАСОСА ====================
  Future<void> _handlePumpModeWrite(int address, int newValue) async {
    await _performWrite(() async {
      final modbusManager = ModbusManager(context);
      final success = await modbusManager.writeRegister(address, newValue);
      if (success && mounted) {
        _onModeChanged(address, newValue);
        _showSuccess('Режим насоса изменен');
      } else if (mounted) {
        _showError('Ошибка изменения режима');
      }
    });
  }
}
