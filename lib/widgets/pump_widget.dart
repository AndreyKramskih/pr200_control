// lib/widgets/pump_widget.dart
import 'package:flutter/material.dart';
import '../models/config_model.dart';
// import '../services/modbus_manager.dart'; // ❌ Удаляем – больше не нужен

class PumpWidget extends StatelessWidget {
  final ItemConfig item;
  final dynamic value;
  final dynamic modeValue;
  final void Function(int)? onModeChanged;
  final String? pumpId;
  final VoidCallback? onDropdownOpen;
  final VoidCallback? onDropdownClose;
  // ✅ Новый колбэк для записи режима
  final void Function(int, int)? onModeWrite;

  const PumpWidget({
    super.key,
    required this.item,
    this.value,
    this.modeValue,
    this.onModeChanged,
    this.pumpId,
    this.onDropdownOpen,
    this.onDropdownClose,
    this.onModeWrite, // добавляем
  });

  @override
  Widget build(BuildContext context) {
    final isOn = value != null && (value & (1 << (item.bit ?? 0))) != 0;
    final stateText = item.states != null && item.states!.isNotEmpty
        ? (isOn ? item.states![1] : item.states![0])
        : (isOn ? 'Вкл' : 'Выкл');

    final hasMode =
        item.modeAddress != null &&
        item.modeStates != null &&
        item.modeStates!.isNotEmpty;

    print(
      '🔄 PumpWidget: ${item.name}, modeAddress=${item.modeAddress}, modeValue=$modeValue, pumpId=$pumpId',
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings_overscan,
                  size: 36,
                  color: isOn ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        stateText,
                        style: TextStyle(
                          fontSize: 14,
                          color: isOn ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOn ? Colors.green[100] : Colors.red[100],
                    border: Border.all(
                      color: isOn ? Colors.green : Colors.red,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    isOn ? Icons.play_arrow : Icons.stop,
                    color: isOn ? Colors.green : Colors.red,
                    size: 30,
                  ),
                ),
              ],
            ),
            if (hasMode) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    'Режим:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _buildModeDropdown(context)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeDropdown(BuildContext context) {
    final dropdownKey = ValueKey('dropdown_${pumpId ?? item.address}');

    int currentMode = 0;
    if (modeValue is int) {
      currentMode = modeValue;
    }

    final modeStates = item.modeStates!;
    final modeAddress = item.modeAddress!;

    if (currentMode < 0 || currentMode >= modeStates.length) {
      currentMode = 0;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<int>(
        key: dropdownKey,
        value: currentMode,
        isExpanded: true,
        underline: const SizedBox(),
        items: modeStates.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;
          return DropdownMenuItem<int>(value: index, child: Text(label));
        }).toList(),
        onTap: () {
          print('🔽 Dropdown для ${item.name} открыт');
          if (onDropdownOpen != null) {
            onDropdownOpen!();
          }
        },
        onChanged: (newValue) async {
          if (newValue == null) return;

          final pumpName = item.name;
          final address = modeAddress;

          print(
            '🔵 Изменение режима: $pumpName -> ${modeStates[newValue]} (адрес $address)',
          );

          // Показываем уведомление
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⏳ Отправка запроса...'),
                duration: Duration(milliseconds: 300),
              ),
            );
          }

          // ✅ Вызываем колбэк для записи (он обёрнут в _performWrite)
          if (onModeWrite != null) {
            onModeWrite!(address, newValue);
          } else {
            // Если колбэк не передан – показываем ошибку
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('❌ Не удалось изменить режим: колбэк не задан'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }

          // Закрываем dropdown после инициирования записи
          if (onDropdownClose != null) {
            onDropdownClose!();
          }

          // Дополнительная задержка для обновления UI (не обязательна)
          await Future.delayed(const Duration(milliseconds: 300));
        },
      ),
    );
  }
}
