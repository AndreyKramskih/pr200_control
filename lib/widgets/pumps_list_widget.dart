// lib/widgets/pumps_list_widget.dart
import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../widgets/pump_widget.dart';
import '../services/logger_service.dart';

/// Виджет для отображения списка насосов
class PumpsListWidget extends StatefulWidget {
  final SubmenuConfig submenu;
  final Map<String, dynamic> realtimeData;
  final Map<String, dynamic> modeData;
  final VoidCallback onDropdownOpen;
  final VoidCallback onDropdownClose;
  final Function(int, int) onModeChanged; // (itemAddress, newValue)

  const PumpsListWidget({
    super.key,
    required this.submenu,
    required this.realtimeData,
    required this.modeData,
    required this.onDropdownOpen,
    required this.onDropdownClose,
    required this.onModeChanged,
  });

  @override
  State<PumpsListWidget> createState() => _PumpsListWidgetState();
}

class _PumpsListWidgetState extends State<PumpsListWidget> {
  // Храним состояние открытия dropdown для каждого насоса
  final Map<String, bool> _dropdownStates = {};

  void _onDropdownOpen(String pumpId) {
    if (!_dropdownStates.containsKey(pumpId) || !_dropdownStates[pumpId]!) {
      setState(() {
        _dropdownStates[pumpId] = true;
      });
      widget.onDropdownOpen();
    }
  }

  void _onDropdownClose(String pumpId) {
    if (_dropdownStates.containsKey(pumpId) && _dropdownStates[pumpId]!) {
      setState(() {
        _dropdownStates[pumpId] = false;
      });
      widget.onDropdownClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.submenu.items == null || widget.submenu.items!.isEmpty) {
      return const Center(child: Text('Нет насосов'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: widget.submenu.items!.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;

        final value = widget.realtimeData[item.address.toString()];
        final modeValue = item.modeAddress != null
            ? widget.modeData[item.modeAddress.toString()]
            : null;

        final pumpId = 'pump_${index}_${item.address}';

        return PumpWidget(
          item: item,
          value: value,
          modeValue: modeValue,
          pumpId: pumpId,
          key: ValueKey('pump_${item.address}_${modeValue ?? 0}_$index'),
          onDropdownOpen: () => _onDropdownOpen(pumpId),
          onDropdownClose: () => _onDropdownClose(pumpId),
          onModeChanged: (newValue) {
            final address = item.modeAddress!;
            LoggerService().log(
              '🔄 Локальное обновление режима: ${item.name} -> $newValue (адрес $address)',
            );
            widget.onModeChanged(address, newValue);
          },
        );
      }).toList(),
    );
  }
}
