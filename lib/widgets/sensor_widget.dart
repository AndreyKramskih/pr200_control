import 'package:flutter/material.dart';
import '../models/config_model.dart';

class SensorWidget extends StatelessWidget {
  final ItemConfig item;
  final dynamic value;

  const SensorWidget({super.key, required this.item, this.value});

  @override
  Widget build(BuildContext context) {
    final isSetpoint = item.isSetpoint ?? false;
    // Используем иконку из JSON или стандартную
    final icon = item.icon ?? (isSetpoint ? '🎯' : '🌡️');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      color: isSetpoint ? Colors.blue[50] : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSetpoint ? Colors.blue[800] : Colors.black54,
                    ),
                  ),
                ),
                if (isSetpoint)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'УСТАВКА',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blue[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value?.toString() ?? '--',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _getValueColor(),
                  ),
                ),
                Text(
                  item.unit ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    color: isSetpoint ? Colors.blue[700] : Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getValueColor() {
    if (value == null) return Colors.grey;
    if (item.min != null && item.max != null) {
      final numValue = double.tryParse(value.toString());
      if (numValue != null) {
        if (numValue < item.min! || numValue > item.max!) {
          return Colors.red;
        }
        return Colors.green;
      }
    }
    return Colors.black87;
  }
}
