// lib/widgets/pump_widget.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/config_model.dart';
import '../services/modbus_service.dart';

class PumpWidget extends StatelessWidget {
  final ItemConfig item;
  final dynamic value;
  final dynamic modeValue;
  final VoidCallback? onModeChanged;
  final String? pumpId; // ✅ Добавляем уникальный ID для насоса

  const PumpWidget({
    super.key,
    required this.item,
    this.value,
    this.modeValue,
    this.onModeChanged,
    this.pumpId, // ✅ Добавляем
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
            // Верхняя строка: название и статус
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

            // Режим работы (если есть)
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
    final modbus = Provider.of<ModbusService>(context, listen: false);

    // ✅ Используем pumpId для уникального ключа dropdown
    final dropdownKey = ValueKey('dropdown_${pumpId ?? item.address}');

    int currentMode = 0;
    if (modeValue is int) {
      currentMode = modeValue;
    }

    final modeStates = item.modeStates!;
    final modeAddress = item.modeAddress!;

    print(
      '📊 Dropdown для ${item.name}: currentMode=$currentMode, modeAddress=$modeAddress, modeStates=$modeStates',
    );

    if (currentMode < 0 || currentMode >= modeStates.length) {
      print('⚠️ currentMode=$currentMode вне диапазона, устанавливаю 0');
      currentMode = 0;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<int>(
        key: dropdownKey, // ✅ Уникальный ключ
        value: currentMode,
        isExpanded: true,
        underline: const SizedBox(),
        items: modeStates.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;
          return DropdownMenuItem<int>(value: index, child: Text(label));
        }).toList(),
        onChanged: (newValue) async {
          if (newValue == null) return;

          // ✅ Явно указываем, какой насос меняется
          final pumpName = item.name;
          final address = modeAddress;

          print(
            '🔵 Изменение режима: $pumpName -> ${modeStates[newValue]} (адрес $address)',
          );

          final success = await modbus.writeRegister(address, newValue);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  success
                      ? 'Режим насоса "$pumpName" изменен на "${modeStates[newValue]}"'
                      : 'Ошибка изменения режима',
                ),
                backgroundColor: success ? Colors.green : Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );

            if (success) {
              print(
                '✅ Режим записан успешно, вызываю onModeChanged для $pumpName',
              );
              if (onModeChanged != null) {
                onModeChanged!();
              }
            }
          }
        },
      ),
    );
  }
}
