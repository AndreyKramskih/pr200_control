// lib/widgets/valve_widget.dart
import 'package:flutter/material.dart';
import '../models/config_model.dart';

/// Виджет для отображения клапана
class ValveWidget extends StatelessWidget {
  final SubmenuConfig submenu;
  final Map<String, dynamic> realtimeData;
  final Map<String, dynamic> settingsData;
  final VoidCallback onSwitchMode;
  final Function(int, int) onSendCommand;
  final Function(int, dynamic) onSetSetpoint;

  const ValveWidget({
    super.key,
    required this.submenu,
    required this.realtimeData,
    required this.settingsData,
    required this.onSwitchMode,
    required this.onSendCommand,
    required this.onSetSetpoint,
  });

  @override
  Widget build(BuildContext context) {
    final isAnalog = submenu.analog ?? false;

    ItemConfig? positionItem;
    ItemConfig? setpointItem;

    if (isAnalog && submenu.items != null) {
      for (final item in submenu.items!) {
        if (item.name.contains('Текущее положение') &&
            (item.readonly ?? false)) {
          positionItem = item;
        }
        if (item.isSetpoint == true) {
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
          if (item.isSetpoint == true) continue;
        }
        final value = realtimeData[item.address.toString()];
        children.add(_buildValveItem(item, value));
      }
    }

    if (isAnalog && positionItem != null) {
      final value = realtimeData[positionItem.address.toString()];
      children.add(_buildAnalogPosition(positionItem, value));
    }

    if (isAnalog && setpointItem != null) {
      final value =
          settingsData[setpointItem.address.toString()] ??
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

  Widget _buildValveItem(ItemConfig item, dynamic value) {
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
                      onPressed: () => onSwitchMode(),
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
                      onPressed: () => onSwitchMode(),
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

  Widget _buildAnalogPosition(ItemConfig item, dynamic value) {
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
                  'Текущее положение',
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
                      onSetSetpoint(item.address, newValue.round());
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
                    onPressed: () => onSendCommand(item.address, 0),
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
                    onPressed: () => onSendCommand(item.address, 100),
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
              onPressed: () => onSendCommand(item.address, currentValue),
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

  Widget _buildValveControl(ControlConfig control) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          control.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.play_arrow, color: Colors.blue),
        onTap: () => onSendCommand(control.address, control.value),
      ),
    );
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
