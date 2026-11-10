import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../widgets/parameter_widget.dart';
import '../core/utils/theme_utils.dart';

class SettingsWidget extends StatelessWidget {
  final SubmenuConfig submenu;
  final Map<String, dynamic> settingsData;
  final VoidCallback onReloadSettings;
  final VoidCallback onSaveAllSettings;

  // ✅ НОВЫЕ колбэки
  final VoidCallback onSaveSnapshot;
  final VoidCallback onLoadSnapshot;

  final Function(ItemConfig, dynamic) onParamChanged;
  final Function(ItemConfig, dynamic) onParamSave;
  final Future<dynamic> Function(ItemConfig) onParamLoad;

  const SettingsWidget({
    super.key,
    required this.submenu,
    required this.settingsData,
    required this.onReloadSettings,
    required this.onSaveAllSettings,
    required this.onSaveSnapshot,
    required this.onLoadSnapshot,
    required this.onParamChanged,
    required this.onParamSave,
    required this.onParamLoad,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeUtils.isDark(context);

    if (submenu.groups == null || submenu.groups!.isEmpty) {
      return Container(
        color: ThemeUtils.scaffoldColor(context),
        child: const Center(child: Text('Нет настроек')),
      );
    }

    return Container(
      color: ThemeUtils.scaffoldColor(context),
      child: ListView(
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
                    backgroundColor: isDark
                        ? Colors.blue[800]
                        : Colors.blue[100],
                    foregroundColor: isDark ? Colors.white : Colors.blue[800],
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
          // === НОВЫЙ Ряд 2: Память приложения (снимок / загрузить) ===
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSaveSnapshot,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('В память'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                    side: BorderSide(
                      color: isDark ? Colors.grey[600]! : Colors.grey[400]!,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onLoadSnapshot,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Из памяти'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                    side: BorderSide(
                      color: isDark ? Colors.grey[600]! : Colors.grey[400]!,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Измененные параметры подсвечиваются желтым. '
            'Кнопка "Сохранить все" записывает все измененные параметры.'
            '«В память» / «Из памяти» — работа со снимками настроек '
            'для переноса между объектами.',
            style: TextStyle(
              fontSize: 12,
              color: ThemeUtils.textSecondaryColor(context),
            ),
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.blue[300] : Colors.blue,
                    ),
                  ),
                ),
                ...group.items.map((item) {
                  final value =
                      settingsData[item.address.toString()] ??
                      item.defaultValue;
                  return ParameterWidget(
                    item: item,
                    value: value,
                    key: ValueKey('param_${item.address}'),
                    onChanged: (newValue) => onParamChanged(item, newValue),
                    onSave: (newValue) => onParamSave(item, newValue),
                    onLoad: () => onParamLoad(item),
                  );
                }),
                const SizedBox(height: 16),
              ],
            );
          }),
        ],
      ),
    );
  }
}
