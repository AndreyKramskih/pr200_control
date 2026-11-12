import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/config_model.dart';
import '../models/modbus_data.dart';
import 'modbus_manager.dart';
import 'logger_service.dart';

/// Глобальный монитор аварий.
/// Раз в [pollInterval] опрашивает биты аварий во всех системах конфига
/// и уведомляет слушателей об изменениях.
class AlarmMonitor extends ChangeNotifier {
  final BuildContext context;
  AlarmMonitor(this.context);

  // systemId → list of AlarmItem
  final Map<String, List<AlarmItem>> _activeBySystem = {};
  Timer? _timer;
  bool _running = false;
  bool _isPolling = false;

  Map<String, List<AlarmItem>> get activeBySystem =>
      Map.unmodifiable(_activeBySystem);

  bool get hasAnyAlarm => _activeBySystem.values.any((list) => list.isNotEmpty);

  int get totalCount =>
      _activeBySystem.values.fold(0, (sum, list) => sum + list.length);

  List<AlarmItem> alarmsFor(String systemId) =>
      _activeBySystem[systemId] ?? const [];

  bool systemHasAlarm(String systemId) =>
      (_activeBySystem[systemId] ?? const []).isNotEmpty;

  /// Старт фонового опроса. Период по умолчанию — 60 сек.
  void start({Duration pollInterval = const Duration(seconds: 60)}) {
    if (_running) return;
    _running = true;
    _poll();
    _timer = Timer.periodic(pollInterval, (_) => _poll());
    LoggerService().log(
      '🔔 AlarmMonitor запущен (интервал ${pollInterval.inSeconds} с)',
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    LoggerService().log('🔔 AlarmMonitor остановлен');
  }

  /// Принудительный опрос (например, после сброса аварии)
  Future<void> forceRefresh() => _poll();

  Future<void> _poll() async {
    if (_isPolling) return;
    if (!context.mounted) return;

    final config = Provider.of<ConfigModel>(context, listen: false);
    final modbusManager = ModbusManager(context);

    if (!modbusManager.connected) return;

    _isPolling = true;
    try {
      bool changed = false;

      for (final systemEntry in config.systems.entries) {
        final systemId = systemEntry.key;
        final system = systemEntry.value;

        // Собираем все адреса аварий этой системы
        final alarmsByAddress = <int, List<AlarmConfig>>{};
        for (final submenu in system.submenus.values) {
          if (submenu.type != 'alarms' || submenu.alarms == null) continue;
          for (final alarm in submenu.alarms!) {
            alarmsByAddress.putIfAbsent(alarm.address, () => []).add(alarm);
          }
        }

        if (alarmsByAddress.isEmpty) {
          if ((_activeBySystem[systemId] ?? const []).isNotEmpty) {
            _activeBySystem[systemId] = [];
            changed = true;
          }
          continue;
        }

        final result = <AlarmItem>[];
        for (final entry in alarmsByAddress.entries) {
          final regValue = await modbusManager.readRegister(
            entry.key,
            useCache: false,
          );
          if (regValue == null) continue;

          for (final alarm in entry.value) {
            if ((regValue & (1 << alarm.bit)) != 0) {
              result.add(
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

        final prev = _activeBySystem[systemId] ?? const <AlarmItem>[];
        final prevNames = prev.map((a) => a.name).toSet();
        final newNames = result.map((a) => a.name).toSet();
        final same =
            prevNames.length == newNames.length &&
            prevNames.containsAll(newNames);

        if (!same) {
          _activeBySystem[systemId] = result;
          changed = true;
        }
      }

      if (changed && context.mounted) {
        notifyListeners();
      }
    } finally {
      _isPolling = false;
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
