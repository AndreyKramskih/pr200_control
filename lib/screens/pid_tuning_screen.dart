import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/config_model.dart';
import '../models/trend_data.dart';
import '../services/modbus_manager.dart';
import '../services/modbus_service.dart';
import '../services/modbus_rtu_service.dart';
import '../services/logger_service.dart';

/// Экран автоматической настройки ПИД-регулятора по кривой разгона
class PidTuningScreen extends StatefulWidget {
  final String systemId;
  final String submenuId;
  final SubmenuConfig valveSubmenu;

  const PidTuningScreen({
    super.key,
    required this.systemId,
    required this.submenuId,
    required this.valveSubmenu,
  });

  @override
  State<PidTuningScreen> createState() => _PidTuningScreenState();
}

class _PidTuningScreenState extends State<PidTuningScreen> {
  // ─── Настройки теста ───
  double _valveOpening = 50.0;
  final TextEditingController _travelTimeController = TextEditingController(
    text: '30',
  );

  // ─── ВЫБОР ТИПА РЕГУЛЯТОРА ───
  String _controllerType = 'pid'; // 'pid' или 'pi'

  // ─── Выбор датчика ───
  List<ItemConfig> _availableSensors = [];
  ItemConfig? _selectedSensor;

  // ─── Состояние теста ───
  bool _isRunning = false;
  bool _isFinished = false;
  String _statusMessage = 'Ожидание запуска...';

  // ─── Данные кривой ───
  final List<TrendPoint> _curvePoints = [];

  // ─── Для логики теста ───
  Timer? _timer;
  DateTime? _startTime;
  DateTime? _riseStartTime;
  double _initialTemperature = 0;
  double _temperatureHistory = 0;
  int _stableCounter = 0;
  bool _hasStartedRising = false;

  // ─── Результаты расчёта ───
  double? _gainK;
  double? _delayTime;
  double? _timeConstant;

  // ─── Коэффициенты регулятора ───
  double? _kp;
  double? _ti;
  double? _td;

  // ─── Найденные элементы настроек ПИД ───
  ItemConfig? _kpItem;
  ItemConfig? _tiItem;
  ItemConfig? _tdItem;

  // ─── Определение типа клапана ───
  bool get _isAnalog => widget.valveSubmenu.analog ?? false;

  @override
  void initState() {
    super.initState();
    _loadSensors();
    _findPidItems();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _travelTimeController.dispose();
    super.dispose();
  }

  // ─── ПОИСК ЭЛЕМЕНТОВ ПИД В КОНФИГЕ ───

  void _findPidItems() {
    final config = Provider.of<ConfigModel>(context, listen: false);
    final system = config.getSystem(widget.systemId);
    if (system == null) return;

    for (final submenu in system.submenus.values) {
      if (submenu.type != 'settings') continue;

      if (submenu.groups != null) {
        for (final group in submenu.groups!) {
          for (final item in group.items) {
            final name = item.name.toLowerCase();
            if (name.contains('коэф пропорц') ||
                name.contains('пропорц') ||
                name.contains('kp')) {
              _kpItem = item;
              LoggerService().log(
                '🔍 Найден Kp: ${item.name} (адрес ${item.address})',
              );
            }
            if (name.contains('время интегр') ||
                name.contains('интегр') ||
                name.contains('ti')) {
              _tiItem = item;
              LoggerService().log(
                '🔍 Найден Ti: ${item.name} (адрес ${item.address})',
              );
            }
            if (name.contains('время дифференц') ||
                name.contains('диффер') ||
                name.contains('td')) {
              _tdItem = item;
              LoggerService().log(
                '🔍 Найден Td: ${item.name} (адрес ${item.address})',
              );
            }
          }
        }
      }
    }
  }

  // ─── ЗАГРУЗКА ДАТЧИКОВ ───

  void _loadSensors() {
    final config = Provider.of<ConfigModel>(context, listen: false);
    final system = config.getSystem(widget.systemId);
    if (system == null) return;

    final sensors = <ItemConfig>[];

    for (final submenu in system.submenus.values) {
      if (submenu.type != 'sensors') continue;

      if (submenu.items != null) {
        for (final item in submenu.items!) {
          if (_isTemperatureSensor(item)) {
            sensors.add(item);
          }
        }
      }

      if (submenu.groups != null) {
        for (final group in submenu.groups!) {
          for (final item in group.items) {
            if (_isTemperatureSensor(item)) {
              sensors.add(item);
            }
          }
        }
      }
    }

    setState(() {
      _availableSensors = sensors;
      _selectedSensor = _findSupplySensor(sensors);
      if (_selectedSensor == null && sensors.isNotEmpty) {
        _selectedSensor = sensors.first;
      }
    });

    LoggerService().log(
      '🔍 Найдено ${sensors.length} датчиков температуры для ПИД-настройки',
    );
  }

  bool _isTemperatureSensor(ItemConfig item) {
    if (item.type != 'float' && item.type != 'int') return false;
    if (item.bit != null) return false;

    final unit = item.unit?.toLowerCase() ?? '';
    if (unit.contains('°c') || unit.contains('c') || unit.contains('град')) {
      return true;
    }

    final name = item.name.toLowerCase();
    if (name.contains('температур') ||
        name.contains('temp') ||
        name.contains('°c')) {
      return true;
    }

    return false;
  }

  ItemConfig? _findSupplySensor(List<ItemConfig> sensors) {
    final supplyKeywords = ['подач', 'подача', 'прям', 't1', 'tп'];
    for (final keyword in supplyKeywords) {
      for (final sensor in sensors) {
        if (sensor.name.toLowerCase().contains(keyword)) {
          return sensor;
        }
      }
    }
    return null;
  }

  // ─── ПОИСК ЭЛЕМЕНТОВ УПРАВЛЕНИЯ КЛАПАНОМ ───

  ItemConfig? _findModeItem() {
    if (widget.valveSubmenu.items == null) return null;
    for (final item in widget.valveSubmenu.items!) {
      if (item.name.contains('Режим работы')) {
        return item;
      }
    }
    return null;
  }

  ItemConfig? _findSetpointItem() {
    if (widget.valveSubmenu.items == null) return null;
    for (final item in widget.valveSubmenu.items!) {
      if (item.isSetpoint == true) {
        return item;
      }
    }
    return null;
  }

  ControlConfig? _findOpenControl() {
    if (widget.valveSubmenu.controls == null) return null;
    for (final control in widget.valveSubmenu.controls!) {
      if (control.name.contains('Открыть')) {
        return control;
      }
    }
    return null;
  }

  ControlConfig? _findCloseControl() {
    if (widget.valveSubmenu.controls == null) return null;
    for (final control in widget.valveSubmenu.controls!) {
      if (control.name.contains('Закрыть')) {
        return control;
      }
    }
    return null;
  }

  ControlConfig? _findStopControl() {
    if (widget.valveSubmenu.controls == null) return null;
    for (final control in widget.valveSubmenu.controls!) {
      if (control.name.contains('Стоп')) {
        return control;
      }
    }
    return null;
  }

  // ─── ЛОГИКА ТЕСТА ───

  Future<void> _startTest() async {
    if (!mounted) return;

    if (_selectedSensor == null) {
      _showError('Выберите датчик обратной связи');
      return;
    }

    if (!_isAnalog) {
      final travelTime = double.tryParse(_travelTimeController.text);
      if (travelTime == null || travelTime <= 0) {
        _showError('Введите корректное время полного хода клапана');
        return;
      }
    }

    final modbusManager = ModbusManager(context);
    if (!modbusManager.connected) {
      _showError('Нет подключения к контроллеру');
      return;
    }

    final modeItem = _findModeItem();
    if (modeItem == null) {
      _showError('Не найден элемент "Режим работы" в конфигурации');
      return;
    }

    if (_isAnalog) {
      final setpointItem = _findSetpointItem();
      if (setpointItem == null) {
        _showError('Не найден элемент "Заданное положение" в конфигурации');
        return;
      }
    } else {
      final openControl = _findOpenControl();
      final closeControl = _findCloseControl();
      final stopControl = _findStopControl();
      if (openControl == null || closeControl == null || stopControl == null) {
        _showError(
          'Не найдены команды "Открыть", "Закрыть" и "Стоп" в конфигурации',
        );
        return;
      }
    }

    final initialTemp = await modbusManager.readParameterValue(
      _selectedSensor!,
    );
    if (initialTemp == null) {
      _showError('Не удалось прочитать датчик обратной связи');
      return;
    }

    bool isStable = true;
    double lastValue = initialTemp is double
        ? initialTemp
        : (initialTemp as num).toDouble();

    _statusMessage = '⏳ Проверка стабильности температуры...';
    setState(() {});

    for (int i = 0; i < 5; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final currentValue = await modbusManager.readParameterValue(
        _selectedSensor!,
      );
      if (currentValue == null) {
        _showError('Потеря связи с датчиком');
        return;
      }
      final current = currentValue is double
          ? currentValue
          : (currentValue as num).toDouble();
      if ((current - lastValue).abs() > 0.5) {
        isStable = false;
        break;
      }
      lastValue = current;
    }

    if (!isStable) {
      _showError(
        '❌ Процесс не стационарен. Подождите стабилизации температуры.',
      );
      return;
    }

    final travelTime = double.tryParse(_travelTimeController.text) ?? 30;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Подтверждение запуска теста'),
        content: Text(
          'Перед запуском теста убедитесь:\n'
          '1. Регулятор переведён в ручной режим (Start/Stop = 0)\n'
          '2. Процесс стационарен (температура не меняется)\n\n'
          'Программа автоматически:\n'
          '• Переключит клапан в ручной режим\n'
          '${_isAnalog ? '• Откроет клапан на ${_valveOpening.round()}%' : '• Откроет клапан на ${_valveOpening.round()}% (время хода: $travelTime сек)'}\n'
          '• Начнёт запись температуры\n\n'
          'Продолжить?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('▶️ Запустить'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isRunning = true;
      _isFinished = false;
      _statusMessage = '⏳ Открытие клапана...';
      _curvePoints.clear();
    });

    try {
      final successMode = await modbusManager.setBit(
        modeItem.address,
        modeItem.bit ?? 0,
      );
      if (!successMode) {
        _showError('Не удалось переключить клапан в ручной режим');
        setState(() {
          _isRunning = false;
        });
        return;
      }

      if (_isAnalog) {
        final setpointItem = _findSetpointItem()!;
        final openingValue = _valveOpening.round();
        final successSetpoint = await modbusManager.writeRegister(
          setpointItem.address,
          openingValue,
          type: setpointItem.type,
        );
        if (!successSetpoint) {
          _showError('Не удалось установить положение клапана');
          await modbusManager.clearBit(modeItem.address, modeItem.bit ?? 0);
          setState(() {
            _isRunning = false;
          });
          return;
        }
        LoggerService().log('✅ Клапан открыт на ${_valveOpening.round()}%');
      } else {
        final openControl = _findOpenControl()!;
        final stopControl = _findStopControl()!;
        final travelTime = double.tryParse(_travelTimeController.text) ?? 30;
        final openTime = (travelTime * (_valveOpening / 100)).round();

        final successOpen = await modbusManager.writeRegister(
          openControl.address,
          openControl.value,
          type: openControl.type,
        );
        if (!successOpen) {
          _showError('Не удалось подать сигнал "Открыть"');
          await modbusManager.clearBit(modeItem.address, modeItem.bit ?? 0);
          setState(() {
            _isRunning = false;
          });
          return;
        }

        setState(() {
          _statusMessage = '⏳ Открытие клапана (${openTime} сек)...';
        });

        await Future.delayed(Duration(seconds: openTime));

        await modbusManager.writeRegister(
          stopControl.address,
          stopControl.value,
          type: stopControl.type,
        );
        LoggerService().log(
          '✅ Клапан открыт на ${_valveOpening.round()}% (время: $openTime сек)',
        );
      }

      await Future.delayed(const Duration(seconds: 2));

      final startTemp = await modbusManager.readParameterValue(
        _selectedSensor!,
      );
      if (startTemp == null) {
        _showError('Не удалось прочитать начальную температуру');
        await _closeValve(modbusManager);
        setState(() {
          _isRunning = false;
        });
        return;
      }

      _initialTemperature = startTemp is double
          ? startTemp
          : (startTemp as num).toDouble();
      _temperatureHistory = _initialTemperature;
      _stableCounter = 0;
      _hasStartedRising = false;
      _startTime = DateTime.now();
      _riseStartTime = null;

      _curvePoints.add(
        TrendPoint(timestamp: DateTime.now(), value: _initialTemperature),
      );

      setState(() {
        _statusMessage = '📊 Сбор данных...';
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        _collectData();
      });

      LoggerService().log('▶️ Тест ПИД-настройки запущен');
      LoggerService().log('   Начальная температура: $_initialTemperature°C');
      LoggerService().log('   Открытие клапана: ${_valveOpening.round()}%');
      LoggerService().log(
        '   Тип клапана: ${_isAnalog ? "Аналоговый" : "Трёхпозиционный"}',
      );
    } catch (e) {
      _showError('❌ Ошибка запуска теста: $e');
      LoggerService().log('❌ Ошибка запуска теста: $e', level: LogLevel.error);
      setState(() {
        _isRunning = false;
      });
    }
  }

  Future<void> _closeValve(ModbusManager modbusManager) async {
    try {
      if (_isAnalog) {
        final setpointItem = _findSetpointItem();
        if (setpointItem != null) {
          await modbusManager.writeRegister(
            setpointItem.address,
            0,
            type: setpointItem.type,
          );
        }
      } else {
        final closeControl = _findCloseControl();
        final stopControl = _findStopControl();
        if (closeControl != null && stopControl != null) {
          final travelTime = double.tryParse(_travelTimeController.text) ?? 30;
          final closeTime = (travelTime * 2).round();

          await modbusManager.writeRegister(
            closeControl.address,
            closeControl.value,
            type: closeControl.type,
          );
          await Future.delayed(Duration(seconds: closeTime));

          await modbusManager.writeRegister(
            stopControl.address,
            stopControl.value,
            type: stopControl.type,
          );
        }
      }
    } catch (e) {
      LoggerService().log(
        '⚠️ Ошибка закрытия клапана: $e',
        level: LogLevel.warning,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // СБОР ДАННЫХ С АВТОВОССТАНОВЛЕНИЕМ ПОДКЛЮЧЕНИЯ
  // ═══════════════════════════════════════════════════════════════

  Future<void> _collectData() async {
    if (!mounted) return;
    if (_isFinished) return;

    final modbusManager = ModbusManager(context);

    if (!modbusManager.connected) {
      LoggerService().log(
        '⚠️ Потеря связи, попытка восстановления...',
        level: LogLevel.warning,
      );
      final restored = await _reconnect();
      if (!restored) {
        _stopTest();
        _showError('❌ Потеря подключения к контроллеру');
        return;
      }
    }

    try {
      final value = await modbusManager.readParameterValue(_selectedSensor!);
      if (value == null) {
        LoggerService().log(
          '⚠️ Не удалось прочитать датчик, попытка восстановления...',
          level: LogLevel.warning,
        );
        final restored = await _reconnect();
        if (restored) {
          final retryValue = await modbusManager.readParameterValue(
            _selectedSensor!,
          );
          if (retryValue == null) {
            _stopTest();
            _showError('❌ Не удалось прочитать датчик после восстановления');
            return;
          }
          _processDataPoint(retryValue);
          return;
        } else {
          _stopTest();
          _showError('❌ Потеря подключения к контроллеру');
          return;
        }
      }

      _processDataPoint(value);
    } catch (e) {
      LoggerService().log('❌ Ошибка сбора данных: $e', level: LogLevel.error);
      final restored = await _reconnect();
      if (restored) {
        try {
          final retryValue = await modbusManager.readParameterValue(
            _selectedSensor!,
          );
          if (retryValue != null) {
            _processDataPoint(retryValue);
            return;
          }
        } catch (_) {}
      }
      _stopTest();
      _showError('❌ Потеря подключения к контроллеру');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ВОССТАНОВЛЕНИЕ ПОДКЛЮЧЕНИЯ
  // ═══════════════════════════════════════════════════════════════

  Future<bool> _reconnect() async {
    if (!mounted) return false;

    try {
      final config = Provider.of<ConfigModel>(context, listen: false);
      final modbus = Provider.of<ModbusService>(context, listen: false);
      final rtuService = Provider.of<ModbusRtuService>(context, listen: false);

      if (modbus.connected) {
        modbus.disconnect();
      }
      if (rtuService.connected) {
        await rtuService.disconnect();
      }

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return false;

      if (config.connectionType == 'rtu' && config.rtuConfig != null) {
        final success = await rtuService.connect(
          port: config.rtuConfig!.port,
          slaveId: config.modbusServer.slaveId,
          timeout: config.modbusServer.timeout,
          baudRate: config.rtuConfig!.baudRate,
        );
        if (success) {
          LoggerService().log('✅ RTU переподключен');
          return true;
        }
      } else {
        final success = await modbus.connect(
          config.modbusServer.ip,
          port: config.modbusServer.port,
          slaveId: config.modbusServer.slaveId,
          timeout: config.modbusServer.timeout,
        );
        if (success) {
          LoggerService().log('✅ TCP переподключен');
          return true;
        }
      }

      LoggerService().log(
        '❌ Не удалось переподключиться',
        level: LogLevel.error,
      );
      return false;
    } catch (e) {
      LoggerService().log(
        '❌ Ошибка переподключения: $e',
        level: LogLevel.error,
      );
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ОБРАБОТКА ТОЧКИ ДАННЫХ
  // ═══════════════════════════════════════════════════════════════

  void _processDataPoint(dynamic value) {
    if (!mounted) return;

    final currentTemp = value is double ? value : (value as num).toDouble();

    setState(() {
      _curvePoints.add(
        TrendPoint(timestamp: DateTime.now(), value: currentTemp),
      );
    });

    final totalRise = currentTemp - _initialTemperature;

    if (!_hasStartedRising && totalRise > 0.5) {
      _hasStartedRising = true;
      _riseStartTime = DateTime.now();
      LoggerService().log(
        '📈 Рост температуры начался в ${_riseStartTime!.toLocal().toString().substring(0, 19)}',
      );
    }

    final currentInt = currentTemp.round();
    final previousInt = _temperatureHistory.round();

    if (currentInt == previousInt) {
      if (_hasStartedRising) {
        _stableCounter++;
      }
    } else {
      _stableCounter = 0;
    }

    _temperatureHistory = currentTemp;

    if (_stableCounter >= 5 && _hasStartedRising && totalRise >= 2.0) {
      LoggerService().log(
        '✅ Тест завершён: температура стабилизировалась (рост ${totalRise.toStringAsFixed(1)}°C)',
      );
      _stopTest();
      return;
    }

    if (_stableCounter >= 10 && _hasStartedRising && totalRise < 2.0) {
      LoggerService().log(
        '⚠️ Тест завершён: температура стабилизировалась, но рост всего ${totalRise.toStringAsFixed(1)}°C',
      );
      _stopTest();
      if (mounted) {
        setState(() {
          _statusMessage =
              '⚠️ Рост температуры мал (${totalRise.toStringAsFixed(1)}°C). Увеличьте открытие клапана.';
        });
      }
      return;
    }

    if (_startTime != null) {
      final elapsed = DateTime.now().difference(_startTime!);
      if (elapsed.inSeconds > 300) {
        LoggerService().log('⏰ Таймаут теста (5 минут)');
        _stopTest();
        _showError('⏰ Тест превысил 5 минут. Проверьте, открылся ли клапан.');
        return;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _stopTest() async {
    _timer?.cancel();
    _timer = null;

    if (!mounted) return;

    setState(() {
      _statusMessage = '⏳ Закрытие клапана...';
      _isRunning = false;
    });

    final modbusManager = ModbusManager(context);
    final modeItem = _findModeItem();

    try {
      await _closeValve(modbusManager);
      LoggerService().log('✅ Клапан закрыт');

      await Future.delayed(const Duration(seconds: 2));

      if (modeItem != null) {
        await modbusManager.clearBit(modeItem.address, modeItem.bit ?? 0);
        LoggerService().log('✅ Клапан переключен в АВТО-режим');
      }

      _calculateResults();
    } catch (e) {
      LoggerService().log(
        '❌ Ошибка остановки теста: $e',
        level: LogLevel.error,
      );
      if (mounted) {
        setState(() {
          _statusMessage = '⚠️ Тест завершён с ошибкой';
          _isRunning = false;
          _isFinished = true;
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ГЛАВНЫЙ МЕТОД РАСЧЕТА КОЭФФИЦИЕНТОВ
  // ═══════════════════════════════════════════════════════════════

  void _calculateResults() {
    if (_curvePoints.length < 5) {
      setState(() {
        _statusMessage = '⚠️ Недостаточно данных для расчёта';
        _isRunning = false;
        _isFinished = true;
      });
      return;
    }

    final firstTemp = _curvePoints.first.value;
    final lastTemp = _curvePoints.last.value;
    final totalChange = lastTemp - firstTemp;

    if (totalChange.abs() < 2.0) {
      setState(() {
        _statusMessage =
            '⚠️ Рост температуры мал (${totalChange.toStringAsFixed(1)}°C). Увеличьте открытие клапана.';
        _isRunning = false;
        _isFinished = true;
      });
      LoggerService().log(
        '⚠️ Тест не удался: изменение температуры слишком мало (${totalChange.toStringAsFixed(1)}°C)',
      );
      return;
    }

    if (totalChange < 0) {
      setState(() {
        _statusMessage =
            '⚠️ Температура упала, а не выросла. Проверьте направление регулирования.';
        _isRunning = false;
        _isFinished = true;
      });
      LoggerService().log(
        '⚠️ Тест не удался: температура упала (${totalChange.toStringAsFixed(1)}°C)',
      );
      return;
    }

    _gainK = totalChange / _valveOpening;
    _gainK = double.parse(_gainK!.toStringAsFixed(3));

    LoggerService().log('📊 K (усиление) = $_gainK °C/%');

    // if (_riseStartTime != null) {
    //   _delayTime = _riseStartTime!
    //       .difference(_curvePoints.first.timestamp)
    //       .inSeconds
    //       .toDouble();
    // } else {
    //   for (int i = 1; i < _curvePoints.length; i++) {
    //     if (_curvePoints[i].value > _curvePoints[0].value + 0.5) {
    //       _delayTime = i.toDouble();
    //       break;
    //     }
    //   }
    //   _delayTime ??= 0;
    // }

    // Новый расчёт τ через касательную
    _delayTime = _calculateTauByTangent(_curvePoints);
    if (_delayTime == null || _delayTime! < 0) {
      _delayTime = 0;
    }

    LoggerService().log('📊 τ (задержка) = ${_delayTime} сек');

    final targetChange = firstTemp + totalChange * 0.632;
    bool found = false;
    for (int i = 0; i < _curvePoints.length; i++) {
      if (_curvePoints[i].value >= targetChange) {
        final rawTime = i.toDouble();
        final delay = _delayTime ?? 0;
        _timeConstant = rawTime - delay;
        found = true;
        break;
      }
    }
    if (!found || _timeConstant == null || _timeConstant! < 1) {
      _timeConstant = 1;
    }

    LoggerService().log('📊 T (постоянная времени) = ${_timeConstant} сек');

    final K = _gainK!;
    final tau = _delayTime!;
    final T = _timeConstant!;

    if (K <= 0 || tau <= 0 || T <= 0) {
      _showError('Ошибка: получены отрицательные параметры объекта');
      setState(() {
        _isRunning = false;
        _isFinished = true;
        _statusMessage = '❌ Ошибка расчета параметров';
      });
      return;
    }

    // if (_controllerType == 'pi') {
    //   _kp = double.parse((0.9 * T / (K * tau)).toStringAsFixed(2));
    //   _ti = double.parse((3.33 * tau).toStringAsFixed(1));
    //   _td = 0.0;
    // } else {
    //   _kp = double.parse((1.2 * T / (K * tau)).toStringAsFixed(2));
    //   _ti = double.parse((2 * tau).toStringAsFixed(1));
    //   _td = double.parse((0.5 * tau).toStringAsFixed(2));
    // }

    // Расчёт по методу CHR (Cohen-Coon)
    if (_controllerType == 'pi') {
      // ПИ-регулятор
      _kp = double.parse((1.35 / K * (tau / T) + 0.27).toStringAsFixed(2));
      _ti = double.parse(
        (2.5 * tau / (1 + 0.6 * (tau / T))).toStringAsFixed(1),
      );
      _td = 0.0;
    } else {
      // ПИД-регулятор (формулы CHR для ПИД)
      _kp = double.parse((1.35 / K * (tau / T) + 0.27).toStringAsFixed(2));
      _ti = double.parse(
        (2.5 * tau / (1 + 0.6 * (tau / T))).toStringAsFixed(1),
      );
      _td = double.parse(
        (0.37 * tau / (1 + 0.2 * (tau / T))).toStringAsFixed(2),
      );
    }

    setState(() {
      _isRunning = false;
      _isFinished = true;
      _statusMessage = '✅ Тест завершён!';
    });

    final typeText = _controllerType == 'pi' ? 'ПИ' : 'ПИД';
    LoggerService().log('📊 ===== РЕЗУЛЬТАТЫ НАСТРОЙКИ =====');
    LoggerService().log('📊 Параметры объекта:');
    LoggerService().log('   K (усиление) = $K °C/%');
    LoggerService().log('   τ (задержка) = $tau сек');
    LoggerService().log('   T (постоянная) = $T сек');
    LoggerService().log('📊 Коэффициенты регулятора ($typeText):');
    LoggerService().log('   Kp (пропорциональный) = $_kp');
    LoggerService().log('   Ti (интегрирование) = $_ti сек');
    LoggerService().log('   Td (дифференцирование) = $_td сек');
    LoggerService().log('📊 ===================================');
  }

  /// Расчёт времени запаздывания (τ) методом касательной к кривой разгона.
  /// Возвращает время в секундах от начала теста до пересечения касательной
  /// с начальным уровнем температуры.
  double? _calculateTauByTangent(List<TrendPoint> points) {
    if (points.length < 3) return null;

    // 1. Находим точку с максимальной производной (скоростью роста)
    double maxDerivative = 0;
    int maxIndex = 0;
    for (int i = 1; i < points.length - 1; i++) {
      final dy =
          points[i + 1].value - points[i - 1].value; // центральная разность
      final dt = points[i + 1].timestamp
          .difference(points[i - 1].timestamp)
          .inSeconds;
      if (dt <= 0) continue;
      final derivative = dy / dt;
      if (derivative > maxDerivative) {
        maxDerivative = derivative;
        maxIndex = i;
      }
    }

    if (maxDerivative <= 0) return null;

    // 2. Точка касания
    final tangentPoint = points[maxIndex];
    final t0 = tangentPoint.timestamp
        .difference(points.first.timestamp)
        .inSeconds
        .toDouble();
    final y0 = tangentPoint.value;
    final initialTemp = points.first.value;

    // 3. Пересечение касательной с начальной температурой
    //    y = y0 + k*(t - t0)  =>  t = t0 + (initialTemp - y0)/k
    final tau = (initialTemp - y0) / maxDerivative + t0;
    return tau > 0 ? tau : 0;
  }

  // ═══════════════════════════════════════════════════════════════
  // СОХРАНЕНИЕ КОЭФФИЦИЕНТОВ В ПЛК
  // ═══════════════════════════════════════════════════════════════

  Future<void> _savePidParams() async {
    if (_kp == null || _ti == null || _td == null) {
      _showError('Нет рассчитанных коэффициентов для сохранения');
      return;
    }

    if (_kpItem == null) {
      _showError('Не найден элемент "Коэф пропорц" в конфигурации');
      return;
    }
    if (_tiItem == null) {
      _showError('Не найден элемент "Время интегр" в конфигурации');
      return;
    }

    final bool isPi = _controllerType == 'pi';

    if (!isPi && _td! > 0 && _tdItem == null) {
      _showError('Не найден элемент "Время дифференц" в конфигурации');
      return;
    }

    final typeText = isPi ? 'ПИ' : 'ПИД';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('💾 Сохранить коэффициенты ($typeText)?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Будут записаны следующие значения:'),
            const SizedBox(height: 8),
            Text(
              '• ${_kpItem!.name}: ${_kp!.toStringAsFixed(2)} → адрес ${_kpItem!.address}',
            ),
            Text(
              '• ${_tiItem!.name}: ${_ti!.toStringAsFixed(1)} → адрес ${_tiItem!.address}',
            ),
            if (isPi)
              const Text(
                '• Td (дифференцирование): 0 (отключено)',
                style: TextStyle(color: Colors.grey),
              )
            else if (_td! > 0 && _tdItem != null)
              Text(
                '• ${_tdItem!.name}: ${_td!.toStringAsFixed(2)} → адрес ${_tdItem!.address}',
              )
            else
              const Text(
                '• Td (дифференцирование): 0',
                style: TextStyle(color: Colors.grey),
              ),
            const SizedBox(height: 12),
            Text(
              '⚠️ Убедитесь, что регулятор переведён в ручной режим!',
              style: TextStyle(color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final modbusManager = ModbusManager(context);
    if (!modbusManager.connected) {
      _showError('Нет подключения к ПЛК');
      return;
    }

    setState(() {
      _statusMessage = '⏳ Сохранение коэффициентов...';
    });

    try {
      bool allSuccess = true;

      final kpValue = _kp!.round();
      final successKp = await modbusManager.writeRegister(
        _kpItem!.address,
        kpValue,
        type: _kpItem!.type,
      );
      if (!successKp) {
        allSuccess = false;
        LoggerService().log('❌ Ошибка сохранения Kp', level: LogLevel.error);
      } else {
        LoggerService().log(
          '✅ Kp сохранён: $kpValue → адрес ${_kpItem!.address}',
        );
      }

      final tiValue = _ti!.round();
      final successTi = await modbusManager.writeRegister(
        _tiItem!.address,
        tiValue,
        type: _tiItem!.type,
      );
      if (!successTi) {
        allSuccess = false;
        LoggerService().log('❌ Ошибка сохранения Ti', level: LogLevel.error);
      } else {
        LoggerService().log(
          '✅ Ti сохранён: $tiValue → адрес ${_tiItem!.address}',
        );
      }

      if (_tdItem != null) {
        final tdValue = isPi ? 0 : (_td! > 0 ? _td!.round() : 0);
        final successTd = await modbusManager.writeRegister(
          _tdItem!.address,
          tdValue,
          type: _tdItem!.type,
        );
        if (!successTd) {
          allSuccess = false;
          LoggerService().log('❌ Ошибка сохранения Td', level: LogLevel.error);
        } else {
          LoggerService().log(
            '✅ Td сохранён: $tdValue → адрес ${_tdItem!.address}${isPi ? ' (ПИ-регулятор, Td=0)' : ''}',
          );
        }
      } else {
        LoggerService().log('ℹ️ Td отключён (элемент не найден в конфиге)');
      }

      if (allSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Коэффициенты ($typeText) сохранены в ПЛК!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _statusMessage = '✅ Коэффициенты сохранены!';
        });

        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.pop(context, true);
          }
        });
      } else if (mounted) {
        _showError('❌ Ошибка при сохранении некоторых коэффициентов');
      }
    } catch (e) {
      LoggerService().log('❌ Ошибка сохранения: $e', level: LogLevel.error);
      _showError('❌ Ошибка сохранения: $e');
    } finally {
      if (mounted) {
        setState(() {
          _statusMessage = '✅ Тест завершён!';
        });
      }
    }
  }

  // ─── ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ───

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() {
        _statusMessage = message;
      });
    }
  }

  // ─── BUILD ───

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('⚙️ ПИД-настройка'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _timer?.cancel();
            Navigator.pop(context);
          },
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [Colors.grey[900]!, Colors.grey[800]!]
                : [Colors.grey[50]!, Colors.grey[200]!],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingsCard(isDark),
              const SizedBox(height: 16),
              _buildStatusCard(isDark),
              const SizedBox(height: 16),
              _buildControlButtons(),
              const SizedBox(height: 16),
              _buildGraphCard(isDark),
              const SizedBox(height: 16),
              if (_isFinished) _buildResultsCard(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard(bool isDark) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? Colors.grey[850] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📋 Настройки теста',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _isAnalog ? Icons.speed : Icons.swap_vert,
                    color: _isAnalog ? Colors.blue : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isAnalog ? 'Аналоговый клапан' : 'Трёхпозиционный клапан',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            const Text('Открытие клапана:'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _valveOpening,
                    min: 10,
                    max: 100,
                    divisions: 90,
                    label: '${_valveOpening.round()}%',
                    onChanged: _isRunning
                        ? null
                        : (value) {
                            setState(() {
                              _valveOpening = value;
                            });
                          },
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${_valveOpening.round()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            if (!_isAnalog) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _travelTimeController,
                      enabled: !_isRunning,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Время полного хода (сек)',
                        border: OutlineInputBorder(),
                        helperText: 'Время от 0% до 100%',
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const Divider(),

            const Text(
              'Тип регулятора:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('ПИД'),
                    value: 'pid',
                    groupValue: _controllerType,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: _isRunning
                        ? null
                        : (value) {
                            setState(() => _controllerType = value!);
                          },
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('ПИ'),
                    value: 'pi',
                    groupValue: _controllerType,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: _isRunning
                        ? null
                        : (value) {
                            setState(() => _controllerType = value!);
                          },
                  ),
                ),
              ],
            ),
            if (_controllerType == 'pi')
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.grey[700]! : Colors.blue[200]!,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: isDark ? Colors.blue[300] : Colors.blue[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ПИ-регулятор: дифференцирование (Td) будет отключено (установлено в 0)',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.blue[300] : Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            const Text('Датчик обратной связи:'),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<ItemConfig>(
                value: _selectedSensor,
                isExpanded: true,
                hint: const Text('Выберите датчик'),
                dropdownColor: isDark ? Colors.grey[800] : Colors.white,
                underline: const SizedBox(),
                items: _availableSensors.map((sensor) {
                  return DropdownMenuItem<ItemConfig>(
                    value: sensor,
                    child: Text(
                      '${sensor.icon ?? "🌡️"} ${sensor.name} (${sensor.unit ?? "°C"})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: _isRunning
                    ? null
                    : (value) {
                        setState(() {
                          _selectedSensor = value;
                        });
                      },
              ),
            ),

            if (_kpItem != null || _tiItem != null || _tdItem != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📍 Найдены адреса для сохранения:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_kpItem != null)
                        Text(
                          '  • Kp: ${_kpItem!.name} → адрес ${_kpItem!.address}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      if (_tiItem != null)
                        Text(
                          '  • Ti: ${_tiItem!.name} → адрес ${_tiItem!.address}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      if (_tdItem != null)
                        Text(
                          '  • Td: ${_tdItem!.name} → адрес ${_tdItem!.address}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      if (_controllerType == 'pi')
                        Text(
                          '  • Td будет установлен в 0 (отключён)',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(bool isDark) {
    final isStable = _statusMessage.contains('✅');
    final isError =
        _statusMessage.contains('❌') || _statusMessage.contains('⚠️');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? Colors.grey[850] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _isRunning
                  ? Icons.timer
                  : (_isFinished ? Icons.check_circle : Icons.info_outline),
              color: _isRunning
                  ? Colors.orange
                  : (_isFinished ? Colors.green : Colors.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _statusMessage,
                style: TextStyle(
                  fontSize: 14,
                  color: isError
                      ? Colors.red
                      : (isStable
                            ? Colors.green
                            : (isDark ? Colors.white : Colors.black87)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isRunning ? null : _startTest,
            icon: const Icon(Icons.play_arrow),
            label: const Text('▶️ Старт'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isRunning ? _stopTest : null,
            icon: const Icon(Icons.stop),
            label: const Text('⏹️ Стоп'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              disabledBackgroundColor: Colors.grey,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGraphCard(bool isDark) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? Colors.grey[850] : Colors.white,
      child: SizedBox(
        height: 250,
        width: double.infinity,
        child: _curvePoints.isEmpty
            ? const Center(
                child: Text(
                  'График будет построен после запуска теста',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : CustomPaint(
                painter: TrendPainterSimple(
                  points: _curvePoints,
                  isDark: isDark,
                ),
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // КАРТОЧКА РЕЗУЛЬТАТОВ
  // ═══════════════════════════════════════════════════════════════

  Widget _buildResultsCard(bool isDark) {
    final typeText = _controllerType == 'pi' ? 'ПИ' : 'ПИД';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? Colors.blue[900]?.withOpacity(0.2) : Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📊 Результаты расчёта ($typeText)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            const Text(
              'Параметры объекта:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _buildResultItem(
                    'K (усиление)',
                    _gainK,
                    '°C/%',
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildResultItem(
                    'τ (задержка)',
                    _delayTime,
                    'сек',
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildResultItem(
                    'T (инерция)',
                    _timeConstant,
                    'сек',
                    Colors.purple,
                  ),
                ),
              ],
            ),

            const Divider(),
            const SizedBox(height: 4),

            const Text(
              'Коэффициенты регулятора:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),

            Row(
              children: [
                Expanded(
                  child: _buildResultItem(
                    'Kp (пропорц.)',
                    _kp,
                    '',
                    Colors.green,
                    fontSize: 22,
                  ),
                ),
                Expanded(
                  child: _buildResultItem(
                    'Ti (интегр.)',
                    _ti,
                    'сек',
                    Colors.orange,
                    fontSize: 22,
                  ),
                ),
                Expanded(
                  child: _buildResultItem(
                    'Td (дифф.)',
                    _td,
                    'сек',
                    _td! > 0 ? Colors.red : Colors.grey,
                    fontSize: 22,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            if (_kpItem != null || _tiItem != null || _tdItem != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📍 Будет сохранено в:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (_kpItem != null)
                      Text(
                        '  • ${_kpItem!.name} = ${_kp?.toStringAsFixed(0) ?? "--"} → адрес ${_kpItem!.address}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    if (_tiItem != null)
                      Text(
                        '  • ${_tiItem!.name} = ${_ti?.toStringAsFixed(0) ?? "--"} → адрес ${_tiItem!.address}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    if (_tdItem != null && _td! > 0)
                      Text(
                        '  • ${_tdItem!.name} = ${_td?.toStringAsFixed(0) ?? "--"} → адрес ${_tdItem!.address}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    if (_controllerType == 'pi')
                      const Text(
                        '  • Td (дифференцирование) = 0 (отключено)',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _kp == null ? null : _savePidParams,
                icon: const Icon(Icons.save),
                label: Text('💾 Сохранить ($typeText) в ПЛК'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: isDark ? Colors.amber[300] : Colors.amber[700],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Нажмите "Сохранить" для записи коэффициентов в контроллер.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultItem(
    String label,
    double? value,
    String unit,
    Color color, {
    double fontSize = 16,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          value != null
              ? '${value.toStringAsFixed(value % 1 == 0 ? 0 : (value > 10 ? 1 : 2))} $unit'
              : '--',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─── РИСОВАТЕЛЬ ГРАФИКА ───

class TrendPainterSimple extends CustomPainter {
  final List<TrendPoint> points;
  final bool isDark;

  TrendPainterSimple({required this.points, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    const padding = 30.0;
    final graphWidth = size.width - padding * 2;
    final graphHeight = size.height - padding * 2;

    double minValue = points.first.value;
    double maxValue = points.first.value;
    for (final p in points) {
      if (p.value < minValue) minValue = p.value;
      if (p.value > maxValue) maxValue = p.value;
    }

    final range = maxValue - minValue;
    final yRange = range < 0.1 ? 10.0 : range;

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path();

    for (int i = 0; i < points.length; i++) {
      final x = padding + (i / (points.length - 1)) * graphWidth;
      final y =
          padding +
          graphHeight -
          ((points[i].value - minValue) / yRange) * graphHeight;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    final last = points.last;
    final lastX =
        padding + ((points.length - 1) / (points.length - 1)) * graphWidth;
    final lastY =
        padding +
        graphHeight -
        ((last.value - minValue) / yRange) * graphHeight;

    final pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(lastX, lastY), 4, pointPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '${last.value.toStringAsFixed(1)}°C',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white : Colors.black87,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (lastX - textPainter.width / 2).clamp(
          0,
          size.width - textPainter.width,
        ),
        (lastY - textPainter.height - 6).clamp(
          0,
          size.height - textPainter.height,
        ),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
