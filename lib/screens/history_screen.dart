// lib/screens/history_screen.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/config_model.dart';
import '../services/owen_cloud_service.dart';
import '../services/logger_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Доступные параметры (из конфига, тип sensors)
  List<ItemConfig> _availableItems = [];
  final Set<ItemConfig> _selectedItems = {};

  // Период
  DateTime _from = DateTime.now().subtract(const Duration(hours: 24));
  DateTime _to = DateTime.now();

  bool _loading = false;
  String _status = '';

  // address -> list of (timestamp, value)
  final Map<int, List<Map<String, dynamic>>> _data = {};

  @override
  void initState() {
    super.initState();
    // Загружаем список параметров после первого кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAvailableItems();
    });
  }

  void _loadAvailableItems() {
    final config = Provider.of<ConfigModel>(context, listen: false);
    final items = <ItemConfig>[];

    for (final system in config.systems.values) {
      for (final submenu in system.submenus.values) {
        if (submenu.type != 'sensors') continue;

        if (submenu.items != null) {
          for (final item in submenu.items!) {
            if ((item.type == 'float' || item.type == 'int') &&
                item.bit == null) {
              items.add(item);
            }
          }
        }
        if (submenu.groups != null) {
          for (final group in submenu.groups!) {
            for (final item in group.items) {
              if ((item.type == 'float' || item.type == 'int') &&
                  item.bit == null) {
                items.add(item);
              }
            }
          }
        }
      }
    }

    setState(() => _availableItems = items);
  }

  Future<void> _pickDateTime({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isFrom) {
        _from = dt;
      } else {
        _to = dt;
      }
    });
  }

  Future<void> _loadHistory() async {
    if (_selectedItems.isEmpty) {
      setState(() => _status = 'Выберите хотя бы один параметр');
      return;
    }

    if (_to.isBefore(_from)) {
      setState(() => _status = 'Дата «по» раньше даты «с»');
      return;
    }

    final cloud = Provider.of<OwenCloudService>(context, listen: false);
    if (!cloud.connected) {
      setState(() => _status = 'История доступна только в Owen Cloud');
      return;
    }

    setState(() {
      _loading = true;
      _status = 'Загрузка...';
      _data.clear();
    });

    try {
      final addresses = _selectedItems.map((e) => e.address).toList();
      final result = await cloud.readHistory(
        addresses: addresses,
        from: _from,
        to: _to,
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _data.addAll(result);
        _status = result.isEmpty
            ? 'Нет данных за выбранный период'
            : 'Загружено ${result.length} из ${addresses.length} параметров';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Ошибка: $e';
      });
      LoggerService().log('❌ История: $e', level: LogLevel.error);
    }
  }

  Future<void> _exportToCsv() async {
    if (_data.isEmpty) {
      setState(() => _status = 'Нет данных для экспорта');
      return;
    }

    try {
      final selectedList = _selectedItems.toList();

      // === Формируем CSV ===
      final buffer = StringBuffer();
      // BOM для Excel, чтобы русские буквы не превращались в кракозябры
      buffer.writeCharCode(0xFEFF);

      // Заголовки
      final header = <String>['Время'];
      for (final item in selectedList) {
        final unit = (item.unit != null && item.unit!.isNotEmpty)
            ? ' (${item.unit})'
            : '';
        header.add('"${item.name}$unit"');
      }
      buffer.writeln(header.join(';'));

      // Собираем все временные метки
      final allTimestamps = <DateTime>{};
      for (final rows in _data.values) {
        for (final row in rows) {
          allTimestamps.add(row['timestamp'] as DateTime);
        }
      }
      final sorted = allTimestamps.toList()..sort();

      // address → timestamp → value
      final lookup = <int, Map<DateTime, String>>{};
      for (final entry in _data.entries) {
        lookup[entry.key] = {
          for (final r in entry.value)
            r['timestamp'] as DateTime: r['value'] as String,
        };
      }

      // Строки данных
      for (final ts in sorted) {
        final row = <String>[_fmtFull(ts)];
        for (final item in selectedList) {
          final v = lookup[item.address]?[ts] ?? '';
          row.add('"${v.replaceAll('"', '""')}"');
        }
        buffer.writeln(row.join(';'));
      }

      // === Сохраняем во временную папку приложения ===
      // (не в Android/data — она скрыта от файловых менеджеров)
      final tmpDir = Directory.systemTemp;
      final dateStr = DateTime.now()
          .toIso8601String()
          .substring(0, 19)
          .replaceAll(':', '-');
      final fileName = 'История_$dateStr.csv';
      final file = File('${tmpDir.path}/$fileName');
      await file.writeAsString(buffer.toString(), encoding: utf8);

      // === Открываем системное меню «Поделиться» ===
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'История параметров PR200',
          text:
              'Файл истории параметров с ${_fmtShort(_from)} по ${_fmtShort(_to)}',
        ),
      );

      if (mounted) {
        setState(() => _status = 'Файл подготовлен к отправке');
      }
    } catch (e) {
      LoggerService().log('❌ Экспорт CSV: $e', level: LogLevel.error);
      if (mounted) {
        setState(() => _status = 'Ошибка экспорта: $e');
      }
    }
  }

  String _fmtShort(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  String _fmtFull(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.'
      '${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('История параметров'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _data.isEmpty ? null : _exportToCsv,
            tooltip: 'Экспорт в CSV',
          ),
        ],
      ),
      body: Column(
        children: [
          // === Период ===
          Container(
            padding: const EdgeInsets.all(12),
            color: isDark ? Colors.grey[850] : Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      'С ${_fmtShort(_from)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _loading
                        ? null
                        : () => _pickDateTime(isFrom: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      'По ${_fmtShort(_to)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _loading
                        ? null
                        : () => _pickDateTime(isFrom: false),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download, color: Colors.green),
                  onPressed: _loading ? null : _loadHistory,
                  tooltip: 'Загрузить',
                ),
              ],
            ),
          ),

          // === Список параметров ===
          Expanded(
            flex: 2,
            child: Material(
              color: isDark ? Colors.grey[900] : Colors.white,
              child: _availableItems.isEmpty
                  ? const Center(child: Text('Нет доступных параметров'))
                  : ListView.builder(
                      itemCount: _availableItems.length,
                      itemBuilder: (context, index) {
                        final item = _availableItems[index];
                        final selected = _selectedItems.contains(item);
                        return CheckboxListTile(
                          key: ValueKey('hist_item_${item.address}'),
                          dense: true,
                          title: Text(item.name),
                          subtitle: Text(item.unit ?? ''),
                          value: selected,
                          onChanged: _loading
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selectedItems.add(item);
                                    } else {
                                      _selectedItems.remove(item);
                                    }
                                  });
                                },
                        );
                      },
                    ),
            ),
          ),

          // === Статус ===
          if (_status.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              color: isDark ? Colors.grey[850] : Colors.grey[200],
              child: Text(_status, style: const TextStyle(fontSize: 12)),
            ),

          // === Таблица ===
          Expanded(
            flex: 3,
            child: Material(
              color: isDark ? Colors.grey[900] : Colors.white,
              child: _buildTable(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(bool isDark) {
    if (_data.isEmpty) {
      return const Center(
        child: Text('Выберите параметры и нажмите «Загрузить»'),
      );
    }

    // Объединяем все временные метки
    final allTimestamps = <DateTime>{};
    for (final rows in _data.values) {
      for (final row in rows) {
        allTimestamps.add(row['timestamp'] as DateTime);
      }
    }
    final sorted = allTimestamps.toList()..sort();

    // address → timestamp → value
    final lookup = <int, Map<DateTime, String>>{};
    for (final entry in _data.entries) {
      lookup[entry.key] = {
        for (final r in entry.value)
          r['timestamp'] as DateTime: r['value'] as String,
      };
    }

    final selectedList = _selectedItems.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            isDark ? Colors.grey[800] : Colors.grey[200],
          ),
          columns: [
            const DataColumn(label: Text('Время')),
            ...selectedList.map((item) => DataColumn(label: Text(item.name))),
          ],
          rows: sorted.take(500).map((ts) {
            return DataRow(
              cells: [
                DataCell(Text(_fmtFull(ts))),
                ...selectedList.map((item) {
                  final v = lookup[item.address]?[ts] ?? '';
                  return DataCell(Text(v));
                }),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
