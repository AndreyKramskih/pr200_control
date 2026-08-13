// lib/widgets/settings_widget.dart
import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../widgets/parameter_widget.dart';

/// Виджет для отображения настроек
class SettingsWidget extends StatelessWidget {
  final SubmenuConfig submenu;
  final Map<String, dynamic> settingsData;
  final VoidCallback onReloadSettings;
  final VoidCallback onSaveAllSettings;
  final Function(ItemConfig, dynamic) onParamChanged;
  final Function(ItemConfig, dynamic) onParamSave;
  final Future<dynamic> Function(ItemConfig) onParamLoad;

  const SettingsWidget({
    super.key,
    required this.submenu,
    required this.settingsData,
    required this.onReloadSettings,
    required this.onSaveAllSettings,
    required this.onParamChanged,
    required this.onParamSave,
    required this.onParamLoad,
  });

  @override
  Widget build(BuildContext context) {
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
                onPressed: onReloadSettings,
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
                onPressed: onSaveAllSettings,
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
                    settingsData[item.address.toString()] ?? item.defaultValue;
                return ParameterWidget(
                  item: item,
                  value: value,
                  key: ValueKey('param_${item.address}'),
                  onChanged: (newValue) => onParamChanged(item, newValue),
                  onSave: (newValue) => onParamSave(item, newValue),
                  onLoad: () => onParamLoad(item),
                );
              }).toList(),
              const SizedBox(height: 16),
            ],
          );
        }).toList(),
      ],
    );
  }
}
