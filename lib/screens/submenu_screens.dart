// lib/screens/submenu_screens.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/config_model.dart';
import '../models/modbus_data.dart';
import '../services/modbus_manager.dart';
import '../services/logger_service.dart';
import '../widgets/sensors_list_widget.dart';
import '../widgets/relays_list_widget.dart';
import '../widgets/pumps_list_widget.dart';
import '../widgets/alarms_widget.dart';
import '../widgets/valve_widget.dart';
import '../widgets/start_stop_widget.dart';
import '../widgets/settings_widget.dart';
import '../widgets/device_status_banner.dart';

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

  final Map<String, dynamic> _realtimeData = {};
  final Map<String, dynamic> _modeData = {};
  final Map<String, dynamic> _settingsData = {};
  final List<AlarmItem> _alarms = [];

  Timer? _updateTimer;
  bool _active = true;

  bool _settingsLoadingShown = false;

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
  void deactivate() {
    _active = false;
    _updateTimer?.cancel();
    _updateTimer = null;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    if (_isRealtimeType) {
      _startAutoUpdate();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _updateTimer = null;
    super.dispose();
  }

  // ==================== УНИВЕРСАЛЬНЫЙ МЕТОД ДЛЯ ЗАПИСИ ====================

  Future<void> _performWrite(Future<void> Function() writeOperation) async {
    _updateTimer?.cancel();
    try {
      await writeOperation();
    } finally {
      if (_active && mounted && _isRealtimeType) {
        _startAutoUpdate();
      }
    }
  }

  void _startAutoUpdate() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_active || !mounted) {
        timer.cancel();
        return;
      }
      if (_isDropdownOpen || _isResettingAlarms) return;
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
    if (!_active) return;

    if (_isSettingsType) {
      await _loadSettingsData(submenu);
      if (!_active) return;
    }

    if (_isPumpsType) {
      await _loadPumpModes(submenu);
      if (!_active) return;
    }

    if (mounted && _active) {
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
        if (!_active) return;
        for (final entry in intResults.entries) {
          newData['${entry.key}'] = entry.value;
        }
      }

      if (floatAddresses.isNotEmpty) {
        final floatResults = await modbusManager.readMultipleFloats(
          floatAddresses,
        );
        if (!_active) return;
        for (final entry in floatResults.entries) {
          newData['${entry.key}'] = entry.value;
        }
      }
    }

    if (mounted && _active) {
      setState(() {
        _realtimeData.clear();
        _realtimeData.addAll(newData);
      });
      LoggerService().log(
        '✅ _loadRealtimeData: загружено ${_realtimeData.length} значений',
      );
    }

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
          if (!_active) return;

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

      if (mounted && _active) {
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
    if (!mounted || !_active) return;
    if (_isDropdownOpen || _isResettingAlarms) return;

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
        if (!_active) return;
        for (final entry in intResults.entries) {
          newData['${entry.key}'] = entry.value;
        }
      }

      if (floatAddresses.isNotEmpty) {
        final floatResults = await modbusManager.readMultipleFloats(
          floatAddresses,
        );
        if (!_active) return;
        for (final entry in floatResults.entries) {
          newData['${entry.key}'] = entry.value;
        }
      }
    }

    if (mounted && _active) {
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
          if (!_active) return;

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
          // Игнорируем ошибки
        }
      }

      if (mounted && _active) {
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
        if (!_active) return;
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

    if (hasChanges && mounted && _active) {
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
      if (!_active) return;
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
      if (!_active) return;
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

    if (mounted && _active) {
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
    if (!mounted || !_active) return;

    final config = Provider.of<ConfigModel>(context, listen: false);
    final system = config.getSystem(widget.systemId);
    if (system == null) return;

    final submenu = system.submenus[widget.submenuId];
    if (submenu == null) return;

    await _loadSettingsData(submenu);

    if (mounted && _active) {
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
    if (!mounted || !_active) return;

    final config = Provider.of<ConfigModel>(context, listen: false);
    final system = config.getSystem(widget.systemId);
    if (system == null) return;

    final submenu = system.submenus[widget.submenuId];
    if (submenu == null) return;

    await _loadRealtimeData(submenu);
    if (!_active) return;

    if (_isSettingsType) {
      await _loadSettingsData(submenu);
      if (!_active) return;
    }

    if (_isPumpsType) {
      await _loadPumpModes(submenu);
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

      // ✅ Показываем индикатор, что идёт проверка параметров
      _showSettingsLoading();

      // Небольшая пауза, чтобы диалог успел отрисоваться
      await Future.delayed(const Duration(milliseconds: 100));

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
              if (!_active) {
                _hideSettingsLoading();
                return;
              }

              if (currentValue != null && newValue != currentValue) {
                changedValues[item.address] = newValue;
              }
            }
          }
        }
      }

      // ✅ Прячем индикатор — сбор завершён
      _hideSettingsLoading();
      if (!_active) return;

      if (changedValues.isEmpty) {
        _showSuccess('Нет измененных параметров для сохранения');
        return;
      }
      LoggerService().log(
        '🔵 Сохранение ${changedValues.length} измененных параметров...)',
      );

      final messenger = ScaffoldMessenger.maybeOf(context);
      final navigator = Navigator.of(context);
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
              }),
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

      if (!mounted || !_active || confirm != true) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('Параметры сохранены')),
      );

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
        if (!_active) return;
        if (!success) allSuccess = false;
      }

      if (floatValues.isNotEmpty) {
        final success = await modbusManager.writeMultipleRegisters(
          floatValues,
          type: 'float',
        );
        if (!_active) return;
        if (!success) allSuccess = false;
      }

      if (mounted && _active) {
        if (allSuccess) {
          _showSuccess('Все параметры сохранены!${_cloudDelayHint()}');
          await _reloadSettings();
        } else {
          _showError('Ошибка сохранения: ${modbusManager.lastError}');
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
      if (!mounted || !_active) return;
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
      if (modeItem == null) {
        _showError('Не найден элемент "Режим работы"');
        return;
      }

      final modbusManager = ModbusManager(context);

      final success = await modbusManager.toggleBit(
        modeItem.address,
        modeItem.bit ?? 0,
      );
      if (!_active) return;

      if (success) {
        final currentValue = await modbusManager.readRegister(modeItem.address);
        if (!_active) return;
        final isManual =
            (currentValue != null) &&
            (currentValue & (1 << (modeItem.bit ?? 0))) != 0;
        _showSuccess(
          (isManual
                  ? 'Режим переключен на РУЧНОЙ'
                  : 'Режим переключен на АВТО') +
              _cloudDelayHint(),
        );
        await _loadRealtimeData(submenu);
      } else {
        _showError('Ошибка: ${modbusManager.lastError}');
      }
    });
  }

  Future<void> _sendValveCommand(int address, int value) async {
    await _performWrite(() async {
      if (!mounted || !_active) return;

      final modbusManager = ModbusManager(context);
      final success = await modbusManager.writeRegister(address, value);
      if (!_active) return;
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
    if (!mounted || !_active) return;

    final config = Provider.of<ConfigModel>(context, listen: false);
    final system = config.getSystem(widget.systemId);
    if (system == null) return;
    final submenu = system.submenus[widget.submenuId];
    if (submenu == null) return;
    if (submenu.resetAddress == null) return;

    final resetAddress = submenu.resetAddress!;
    final resetBit = submenu.resetBit ?? 3;

    final startStopBit = system.findFirstBitBySubmenuType('startstop');
    final modeBit = system.findModeBitInValve();

    LoggerService().log(
      '🔍 Найден Start/Stop бит: ${startStopBit ?? "не найден"}',
    );
    LoggerService().log('🔍 Найден Mode бит: ${modeBit ?? "не найден"}');

    final modbusManager = ModbusManager(context);

    if (!modbusManager.connected) {
      if (mounted && _active) {
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

    if (confirm != true || !mounted || !_active) return;

    setState(() {
      _isResettingAlarms = true;
      _isLoading = true;
    });

    try {
      LoggerService().log(
        '🔄 Сброс аварий: адрес=$resetAddress, бит=$resetBit',
      );

      if (mounted && _active) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⏳ Сброс аварий...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final success = await modbusManager.resetAlarms(
        resetAddress: resetAddress,
        resetBit: resetBit,
        controlAddress: resetAddress,
        startStopBit: startStopBit ?? 0,
        modeBit: modeBit ?? 1,
      );
      if (!_active) return;

      if (success) {
        if (config.connectionType == 'cloud') {
          await Future.delayed(const Duration(seconds: 5));
          if (!mounted || !_active) return;
        }
        await _loadRealtimeData(submenu);
        if (!_active) return;

        if (mounted && _active) {
          if (_alarms.isEmpty) {
            _showSuccess('✅ Все аварии сброшены!${_cloudDelayHint()}');
          } else {
            _showWarning(
              '⚠️ Остались активные аварии: ${_alarms.map((a) => a.name).join(", ")}\n'
              'Устраните причину и повторите сброс.',
            );
          }
        }
      } else {
        if (mounted && _active) {
          _showError('Ошибка сброса аварий: ${modbusManager.lastError}');
        }
      }
    } catch (e) {
      LoggerService().log('❌ Ошибка сброса аварий: $e', level: LogLevel.error);
      if (mounted && _active) _showError('Ошибка сброса аварий: $e');
    } finally {
      if (mounted && _active) {
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
      if (!mounted || !_active) return;
      final config = Provider.of<ConfigModel>(context, listen: false);
      final system = config.getSystem(widget.systemId);
      if (system == null) return;
      final submenu = system.submenus[widget.submenuId];
      if (submenu == null || submenu.items == null || submenu.items!.isEmpty) {
        return;
      }
      final item = submenu.items!.first;
      final modbusManager = ModbusManager(context);
      final bit = item.bit ?? 0;
      final key = item.address.toString();

      final currentValue = _realtimeData[key];
      final currentVal = currentValue is int ? currentValue : 0;
      final willBeOn = (currentVal & (1 << bit)) == 0;
      final newValue = willBeOn
          ? (currentVal | (1 << bit))
          : (currentVal & ~(1 << bit));

      final success = await modbusManager.toggleBit(item.address, bit);
      if (!_active) return;

      if (!success) {
        _showError('Ошибка: ${modbusManager.lastError}');
        return;
      }

      if (mounted && _active) {
        setState(() {
          _realtimeData[key] = newValue;
        });
      }
      _showSuccess((willBeOn ? 'Включено' : 'Выключено') + _cloudDelayHint());

      await Future.delayed(const Duration(seconds: 5));
      if (!mounted || !_active) return;
      await _loadRealtimeData(submenu);
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
      if (!mounted || !_active) return;

      final modbusManager = ModbusManager(context);
      LoggerService().log(
        '🔵 Сохранение: ${item.name} = $newValue в адрес ${item.address}',
      );

      final success = await modbusManager.writeRegister(
        item.address,
        newValue,
        type: item.type,
      );
      if (!_active) return;

      if (mounted && _active) {
        final msg = success
            ? 'Параметр сохранён${_cloudDelayHint()}'
            : 'Ошибка: ${modbusManager.lastError}';
        final hasHint = msg.contains('Owen Cloud');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: Duration(seconds: hasHint ? 4 : (success ? 2 : 6)),
          ),
        );
      }

      if (success && mounted && _active) {
        await _reloadSettings();
      }
    });
  }

  Future<dynamic> _onParamLoad(ItemConfig item) async {
    if (!mounted || !_active) return null;

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
    if (!_active) return null;
    if (loadedValue != null && mounted && _active) {
      setState(() {
        _settingsData[item.address.toString()] = loadedValue;
      });
    }
    return loadedValue;
  }

  // ==================== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ====================
  /// Возвращает подсказку про задержку Owen Cloud, если активен облачный режим.
  /// В режиме RTU/TCP возвращает пустую строку — сообщение не изменится.
  String _cloudDelayHint() {
    if (!mounted) return '';
    try {
      final config = Provider.of<ConfigModel>(context, listen: false);
      if (config.connectionType == 'cloud') {
        return '\n\n⏳ Изменения появятся в Owen Cloud через несколько секунд.';
      }
    } catch (_) {}
    return '';
  }

  void _showSettingsLoading() {
    if (!mounted || _settingsLoadingShown) return;
    _settingsLoadingShown = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Проверка изменений...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _hideSettingsLoading() {
    if (!mounted || !_settingsLoadingShown) return;
    _settingsLoadingShown = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _showSuccess(String message) {
    if (mounted && _active) {
      final hasHint = message.contains('Owen Cloud');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: Duration(seconds: hasHint ? 4 : 2),
        ),
      );
    }
  }

  void _showError(String message) {
    if (mounted && _active) {
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
    if (mounted && _active) {
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
      body: Column(
        children: [
          const DeviceStatusBanner(),
          Expanded(
            child: RefreshIndicator(
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
          ),
        ],
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
          onModeWrite: _handlePumpModeWrite,
        );
      case 'valve':
        return ValveWidget(
          submenu: submenu,
          realtimeData: _realtimeData,
          settingsData: _settingsData,
          onSwitchMode: _switchValveMode,
          onSendCommand: _sendValveCommand,
          onSetSetpoint: _onSetSetpoint,
          systemId: widget.systemId,
          submenuId: widget.submenuId,
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

  Future<void> _handlePumpModeWrite(int address, int newValue) async {
    await _performWrite(() async {
      final modbusManager = ModbusManager(context);
      final success = await modbusManager.writeRegister(address, newValue);
      if (!_active) return;
      if (success && mounted && _active) {
        _onModeChanged(address, newValue);
        _showSuccess('Режим насоса изменён${_cloudDelayHint()}');
      } else if (mounted && _active) {
        _showError('Ошибка изменения режима: ${modbusManager.lastError}');
      }
    });
  }
}
