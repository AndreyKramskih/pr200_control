// lib/screens/submenu_screens.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/config_model.dart';
import '../models/modbus_data.dart';
import '../services/modbus_manager.dart';
import '../widgets/sensor_widget.dart';
import '../widgets/relay_widget.dart';
import '../widgets/pump_widget.dart';
import '../widgets/parameter_widget.dart';
import '../services/logger_service.dart';
import '../services/modbus_rtu_service.dart'; // ✅ ДОБАВИТЬ ЭТОТ ИМПОРТ

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
  bool _isDropdownOpen = false; // ✅ Флаг: открыт ли dropdown

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

    // Автообновление ТОЛЬКО для реального времени
    if (_isRealtimeType) {
      _startAutoUpdate();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startAutoUpdate() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // ✅ Если dropdown открыт — НЕ обновляем
      if (_isDropdownOpen) {
        print('⏳ Dropdown открыт, обновление приостановлено');
        return;
      }

      // ✅ Проверяем, не идет ли запись в RTU
      try {
        final rtuService = Provider.of<ModbusRtuService>(
          context,
          listen: false,
        );
        if (rtuService.isWriting) {
          print('⏳ Идет запись в RTU, пропускаю обновление');
          return;
        }
      } catch (e) {
        // Игнорируем
      }

      if (mounted && !_isLoading) {
        _updateRealtimeData();
      }
    });
  }

  // ✅ Методы для управления флагом
  void _onDropdownOpen() {
    if (!_isDropdownOpen) {
      print('🔽 Dropdown открыт, таймер остановлен');
      setState(() {
        _isDropdownOpen = true;
      });
      // Таймер автоматически пропустит обновления
    }
  }

  void _onDropdownClose() {
    if (_isDropdownOpen) {
      print('🔼 Dropdown закрыт, таймер возобновлен');
      setState(() {
        _isDropdownOpen = false;
      });
      // ✅ Принудительно обновляем данные после закрытия dropdown
      _updateRealtimeData();
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

    // 1. Загружаем данные реального времени (для всех типов)
    await _loadRealtimeData(submenu);

    // 2. Загружаем настройки (только для settings)
    if (_isSettingsType) {
      await _loadSettingsData(submenu);
    }

    // 3. Загружаем режимы насосов (только для pumps)
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

  /// Загрузка данных реального времени (один раз при открытии)
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

    // ✅ ИСПРАВЛЕННОЕ ЧТЕНИЕ АВАРИЙ (ПО АДРЕСАМ)
    if (submenu.type == 'alarms' &&
        submenu.alarms != null &&
        submenu.alarms!.isNotEmpty) {
      final alarmsByAddress = <int, List<AlarmConfig>>{};
      for (final alarm in submenu.alarms!) {
        alarmsByAddress.putIfAbsent(alarm.address, () => []).add(alarm);
      }

      final allActiveAlarms = <AlarmItem>[];
      for (final entry in alarmsByAddress.entries) {
        final result = await modbusManager.readAlarms(entry.key, entry.value);
        allActiveAlarms.addAll(result);
      }

      if (mounted) {
        setState(() {
          _alarms.clear();
          _alarms.addAll(allActiveAlarms);
        });
      }
    }
  }

  /// Обновление данных реального времени (каждую секунду)
  Future<void> _updateRealtimeData() async {
    if (!mounted) return;

    // ✅ Проверка: если dropdown открыт — НЕ обновляем
    if (_isDropdownOpen) {
      print('⏳ Dropdown открыт, обновление приостановлено');
      return;
    }

    // ✅ Проверка: если идет запись в RTU — пропускаем обновление
    try {
      final rtuService = Provider.of<ModbusRtuService>(context, listen: false);
      if (rtuService.isWriting) {
        print('⏳ Идет запись в RTU, пропускаю обновление');
        return;
      }
    } catch (e) {
      // Если RTU сервис не инициализирован или не в провайдере — игнорируем
      // (это значит, что мы в TCP режиме или сервис еще не создан)
    }

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
  }

  // ==================== РЕЖИМЫ НАСОСОВ (ТОЛЬКО ПРИ ЗАГРУЗКЕ И ИЗМЕНЕНИИ) ====================

  Future<void> _loadPumpModes(SubmenuConfig submenu) async {
    final modbusManager = ModbusManager(context);
    if (!modbusManager.connected) return;

    if (submenu.items == null || submenu.items!.isEmpty) return;
    LoggerService().log('🔵 _loadPumpModes: загрузка режимов насосов...');

    final Map<String, dynamic> newModeData = {};
    bool hasChanges = false;

    for (final item in submenu.items!) {
      if (item.modeAddress != null) {
        // ✅ Читаем по одному регистру для режимов
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

  // ==================== НАСТРОЙКИ (ТОЛЬКО ПРИ ЗАГРУЗКЕ) ====================

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

    // ✅ Читаем int пакетами до 12 регистров
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

    // ✅ Читаем float пакетами до 6 значений (12 регистров)
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

    // Заполняем значения по умолчанию для непрочитанных
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

  // ==================== ОБНОВЛЕНИЕ НАСТРОЕК (ПРИ НАЖАТИИ) ====================

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

    // Обновляем реальное время
    await _loadRealtimeData(submenu);

    // Обновляем настройки если нужно
    if (_isSettingsType) {
      await _loadSettingsData(submenu);
    }

    // Обновляем режимы насосов если нужно
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
    if (!mounted) return;

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

    // Собираем все значения, которые отличаются от текущих в ПЛК
    final Map<int, dynamic> changedValues = <int, dynamic>{};

    if (submenu.groups != null && submenu.groups!.isNotEmpty) {
      for (final group in submenu.groups!) {
        for (final item in group.items) {
          final key = '${item.address}';
          final newValue = _settingsData[key];
          if (newValue != null) {
            // Читаем текущее значение из ПЛК для сравнения
            dynamic currentValue;
            if (item.type == 'float') {
              currentValue = await modbusManager.readFloat(item.address);
            } else {
              currentValue = await modbusManager.readRegister(
                item.address,
                type: item.type,
              );
            }

            // Сравниваем значения
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

    // Показываем диалог подтверждения
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

    // Разделяем int и float
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

    // Записываем все значения
    bool allSuccess = true;

    // Записываем int
    if (intValues.isNotEmpty) {
      final success = await modbusManager.writeMultipleRegisters(
        intValues,
        type: 'int',
      );
      if (!success) allSuccess = false;
    }

    // Записываем float
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
              colors: [Colors.grey[50]!, Colors.grey[200]!],
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
        return _buildSensors(submenu);
      case 'relays':
        return _buildRelays(submenu);
      case 'pumps':
        return _buildPumps(submenu);
      case 'valve':
        return _buildValve(submenu);
      case 'settings':
        return _buildSettings(submenu);
      case 'alarms':
        return _buildAlarms(submenu);
      case 'startstop':
        return _buildStartStop(submenu);
      default:
        return const Center(child: Text('Неизвестный тип подменю'));
    }
  }

  // ==================== ДАТЧИКИ ====================

  Widget _buildSensors(SubmenuConfig submenu) {
    if (submenu.items == null || submenu.items!.isEmpty) {
      return const Center(child: Text('Нет датчиков'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: submenu.items!.map((item) {
        final value = _realtimeData[item.address.toString()];
        return SensorWidget(
          item: item,
          value: value,
          key: ValueKey('sensor_${item.address}'),
        );
      }).toList(),
    );
  }

  // ==================== РЕЛЕ ====================

  Widget _buildRelays(SubmenuConfig submenu) {
    if (submenu.items == null || submenu.items!.isEmpty) {
      return const Center(child: Text('Нет реле'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: submenu.items!.map((item) {
        final value = _realtimeData[item.address.toString()];
        return RelayWidget(
          item: item,
          value: value,
          key: ValueKey('relay_${item.address}'),
        );
      }).toList(),
    );
  }

  // ==================== НАСОСЫ ====================

  // lib/screens/submenu_screens.dart
  Widget _buildPumps(SubmenuConfig submenu) {
    if (submenu.items == null || submenu.items!.isEmpty) {
      return const Center(child: Text('Нет насосов'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: submenu.items!.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;

        final value = _realtimeData[item.address.toString()];
        final modeValue = item.modeAddress != null
            ? _modeData[item.modeAddress.toString()]
            : null;

        final pumpId = 'pump_${index}_${item.address}';

        return PumpWidget(
          item: item,
          value: value,
          modeValue: modeValue,
          pumpId: pumpId,
          key: ValueKey('pump_${item.address}_${modeValue ?? 0}_$index'),
          onDropdownOpen: _onDropdownOpen,
          onDropdownClose: _onDropdownClose,
          // ✅ НЕ перечитываем режимы! Только обновляем локально
          onModeChanged: (newValue) {
            final address = item.modeAddress!;
            LoggerService().log(
              '🔄 Локальное обновление режима: ${item.name} -> $newValue (адрес $address)',
            );

            // ✅ Просто обновляем _modeData локально
            if (mounted) {
              setState(() {
                _modeData[address.toString()] = newValue;
              });
            }
          },
        );
      }).toList(),
    );
  }

  // ==================== КЛАПАН ====================

  Widget _buildValve(SubmenuConfig submenu) {
    final isAnalog = submenu.analog ?? false;

    ItemConfig? positionItem;
    ItemConfig? setpointItem;

    if (isAnalog && submenu.items != null) {
      for (final item in submenu.items!) {
        if (item.name.contains('Текущее положение') &&
            (item.readonly ?? false)) {
          positionItem = item;
        }
        if (item.name.contains('Заданное положение')) {
          setpointItem = item;
        }
      }
    }

    final children = <Widget>[];

    if (submenu.items != null) {
      for (final item in submenu.items!) {
        if (isAnalog) {
          if (item.name.contains('Текущее положение') &&
              (item.readonly ?? false))
            continue;
          if (item.name.contains('Заданное положение')) continue;
        }
        final value = _realtimeData[item.address.toString()];
        children.add(_buildValveItem(item, value, submenu, isAnalog));
      }
    }

    if (isAnalog && positionItem != null) {
      final value = _realtimeData[positionItem.address.toString()];
      children.add(_buildValveItem(positionItem, value, submenu, isAnalog));
    }

    if (isAnalog && setpointItem != null) {
      final value =
          _settingsData[setpointItem.address.toString()] ??
          setpointItem.defaultValue ??
          50;
      children.add(_buildSetpointControl(setpointItem, value));
    }

    if (submenu.controls != null && submenu.controls!.isNotEmpty) {
      children.addAll([
        const SizedBox(height: 16),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Управление клапаном',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ),
        ...submenu.controls!.map((control) => _buildValveControl(control)),
      ]);
    }

    return ListView(padding: const EdgeInsets.all(16), children: children);
  }

  Widget _buildValveItem(
    ItemConfig item,
    dynamic value,
    SubmenuConfig submenu,
    bool isAnalog,
  ) {
    if (item.name.contains('Режим работы')) {
      final isManual = value != null && (value & (1 << (item.bit ?? 0))) != 0;

      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isManual ? Colors.orange[100] : Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isManual ? 'Ручной' : 'Авто',
                      style: TextStyle(
                        color: isManual
                            ? Colors.orange[800]
                            : Colors.green[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _switchValveMode(item, false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isManual
                            ? Colors.grey[300]
                            : Colors.green,
                        foregroundColor: isManual
                            ? Colors.grey[600]
                            : Colors.white,
                      ),
                      child: const Text('АВТО'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _switchValveMode(item, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isManual
                            ? Colors.orange
                            : Colors.grey[300],
                        foregroundColor: isManual
                            ? Colors.white
                            : Colors.grey[600],
                      ),
                      child: const Text('РУЧНОЙ'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (isAnalog &&
        item.name.contains('Текущее положение') &&
        (item.readonly ?? false)) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.speed, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ТОЛЬКО ЧТЕНИЕ',
                      style: TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: value != null
                              ? (value / 100).clamp(0.0, 1.0)
                              : 0.0,
                          backgroundColor: Colors.grey[300],
                          color: _getProgressColor(value),
                          minHeight: 12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          value != null ? '$value%' : '--',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _getStateText(item, value),
                  style: TextStyle(
                    fontSize: 16,
                    color: _getStateColor(item, value),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  item.states != null && value != null
                      ? (item.states!.length > 1
                            ? item.states![(value & (1 << (item.bit ?? 0))) != 0
                                  ? 1
                                  : 0]
                            : item.states![0])
                      : '--',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetpointControl(ItemConfig item, dynamic value) {
    final currentValue = value ?? item.defaultValue ?? 50;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.touch_app, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Заданное положение',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Slider(
                    value: currentValue.toDouble(),
                    min: (item.min ?? 0).toDouble(),
                    max: (item.max ?? 100).toDouble(),
                    divisions: (item.max ?? 100) - (item.min ?? 0),
                    label: '${currentValue.round()}%',
                    onChanged: (newValue) {
                      if (mounted) {
                        setState(() {
                          _settingsData[item.address.toString()] = newValue
                              .round();
                        });
                      }
                    },
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    '${currentValue.round()}%',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final modbusManager = ModbusManager(context);
                      final success = await modbusManager.writeRegister(
                        item.address,
                        0,
                        type: item.type,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              success ? 'Заданное положение: 0%' : 'Ошибка',
                            ),
                            backgroundColor: success
                                ? Colors.green
                                : Colors.red,
                          ),
                        );
                        if (success) {
                          await _updateRealtimeData();
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('0%'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final modbusManager = ModbusManager(context);
                      final success = await modbusManager.writeRegister(
                        item.address,
                        100,
                        type: item.type,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              success ? 'Заданное положение: 100%' : 'Ошибка',
                            ),
                            backgroundColor: success
                                ? Colors.green
                                : Colors.red,
                          ),
                        );
                        if (success) {
                          await _updateRealtimeData();
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('100%'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                final modbusManager = ModbusManager(context);
                final valueToWrite = _settingsData[item.address.toString()];
                if (valueToWrite != null) {
                  final success = await modbusManager.writeRegister(
                    item.address,
                    valueToWrite,
                    type: item.type,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success ? 'Положение установлено' : 'Ошибка',
                        ),
                        backgroundColor: success ? Colors.green : Colors.red,
                      ),
                    );
                    if (success) {
                      await _updateRealtimeData();
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchValveMode(ItemConfig item, bool manual) async {
    if (!mounted) return;

    final modbusManager = ModbusManager(context);

    final currentValue = await modbusManager.readRegister(item.address);
    if (currentValue == null) {
      if (mounted) _showError('Не удалось прочитать текущий режим');
      return;
    }

    final newValue = manual
        ? currentValue | (1 << (item.bit ?? 0))
        : currentValue & ~(1 << (item.bit ?? 0));

    final success = await modbusManager.writeRegister(item.address, newValue);

    if (success && mounted) {
      _showSuccess(
        manual ? 'Режим переключен на РУЧНОЙ' : 'Режим переключен на АВТО',
      );
      await _updateRealtimeData();
    } else if (mounted) {
      _showError('Не удалось переключить режим');
    }
  }

  Widget _buildValveControl(ControlConfig control) {
    final modbusManager = ModbusManager(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          control.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.play_arrow, color: Colors.blue),
        onTap: () async {
          if (!mounted) return;

          final success = await modbusManager.writeRegister(
            control.address,
            control.value,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  success
                      ? 'Команда "${control.name}" отправлена'
                      : 'Ошибка отправки команды',
                ),
                backgroundColor: success ? Colors.green : Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
            if (success) {
              await _updateRealtimeData();
            }
          }
        },
      ),
    );
  }

  // ==================== НАСТРОЙКИ ====================

  Widget _buildSettings(SubmenuConfig submenu) {
    if (submenu.groups == null || submenu.groups!.isEmpty) {
      return const Center(child: Text('Нет настроек'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _reloadSettings,
                icon: const Icon(Icons.refresh),
                label: const Text('Обновить с ПЛК'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[100],
                  foregroundColor: Colors.blue[800],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveAllSettings,
                icon: const Icon(Icons.save),
                label: const Text('Сохранить все'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Измененные параметры подсвечиваются желтым. '
          'Кнопка "Сохранить все" записывает все измененные параметры.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        ...submenu.groups!.map((group) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  group.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
              ...group.items.map((item) {
                final value =
                    _settingsData[item.address.toString()] ?? item.defaultValue;
                return ParameterWidget(
                  item: item,
                  value: value,
                  key: ValueKey('param_${item.address}'),
                  onChanged: (newValue) {
                    if (mounted) {
                      setState(() {
                        _settingsData[item.address.toString()] = newValue;
                      });
                    }
                  },
                  onSave: (newValue) async {
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
                          content: Text(
                            success ? 'Параметр сохранен' : 'Ошибка сохранения',
                          ),
                          backgroundColor: success ? Colors.green : Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }

                    if (success && mounted) {
                      await _reloadSettings();
                    }
                  },
                  onLoad: () async {
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
                  },
                );
              }).toList(),
              const SizedBox(height: 16),
            ],
          );
        }).toList(),
      ],
    );
  }

  // ==================== АВАРИИ ====================

  Widget _buildAlarms(SubmenuConfig submenu) {
    if (_alarms.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Аварий нет',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._alarms.map((alarm) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: Colors.red[50],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.red[300]!, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          alarm.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    alarm.description,
                    style: TextStyle(color: Colors.red[700]),
                  ),
                ],
              ),
            ),
          );
        }).toList(),

        const SizedBox(height: 16),

        if (submenu.resetAddress != null)
          ElevatedButton.icon(
            onPressed: () async {
              if (!mounted) return;

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
                    'Вы уверены, что хотите сбросить все активные аварии?',
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

              // ✅ Используем правильный сброс аварий
              final success = await modbusManager.resetAlarms(513);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Аварии сброшены' : 'Ошибка сброса аварий',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                    duration: const Duration(seconds: 2),
                  ),
                );
                if (success) {
                  // Обновляем аварии
                  await _updateRealtimeData();
                }
              }
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Сбросить аварии'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
      ],
    );
  }

  // ==================== ВКЛ/ВЫКЛ ====================

  Widget _buildStartStop(SubmenuConfig submenu) {
    if (submenu.items == null || submenu.items!.isEmpty) {
      return const Center(child: Text('Нет элементов управления'));
    }

    final item = submenu.items!.first;
    final value = _realtimeData[item.address.toString()];
    final isOn = value != null && (value & (1 << (item.bit ?? 0))) != 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOn ? Colors.green[100] : Colors.red[100],
                border: Border.all(
                  color: isOn ? Colors.green : Colors.red,
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isOn ? Colors.green : Colors.red).withValues(
                      alpha: 0.3,
                    ),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(
                isOn ? Icons.power_settings_new : Icons.power_off,
                size: 60,
                color: isOn ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              item.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              isOn ? 'Включено' : 'Выключено',
              style: TextStyle(
                fontSize: 18,
                color: isOn ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              child: ElevatedButton(
                onPressed: () async {
                  if (!mounted) return;

                  final modbusManager = ModbusManager(context);
                  final currentValue = value ?? 0;
                  final newRegister = isOn
                      ? currentValue & ~(1 << (item.bit ?? 0))
                      : currentValue | (1 << (item.bit ?? 0));

                  final success = await modbusManager.writeRegister(
                    item.address,
                    newRegister,
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success
                              ? 'Состояние изменено'
                              : 'Ошибка изменения состояния',
                        ),
                        backgroundColor: success ? Colors.green : Colors.red,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    if (success) {
                      await _updateRealtimeData();
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isOn ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isOn ? 'Выключить' : 'Включить',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  String _getStateText(ItemConfig item, dynamic value) {
    if (value == null) return '--';
    if (item.states != null && item.states!.isNotEmpty) {
      if (item.states!.length == 2) {
        final isOn = (value is int) && (value & (1 << (item.bit ?? 0))) != 0;
        return isOn ? item.states![1] : item.states![0];
      }
      return item.states![0];
    }
    if (item.bit != null && value is int) {
      return (value & (1 << item.bit!)) != 0 ? 'Вкл' : 'Выкл';
    }
    return value.toString();
  }

  Color _getStateColor(ItemConfig item, dynamic value) {
    if (value == null) return Colors.grey;
    if (item.bit != null && value is int) {
      final isOn = (value & (1 << item.bit!)) != 0;
      return isOn ? Colors.green : Colors.red;
    }
    return Colors.black87;
  }

  Color _getProgressColor(dynamic value) {
    if (value == null) return Colors.grey;
    if (value < 20) return Colors.red;
    if (value < 50) return Colors.orange;
    return Colors.green;
  }
}
