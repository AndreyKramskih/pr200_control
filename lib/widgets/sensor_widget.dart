import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../core/utils/theme_utils.dart';

class SensorWidget extends StatelessWidget {
  final ItemConfig item;
  final dynamic value;

  const SensorWidget({super.key, required this.item, this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeUtils.isDark(context);
    final isSetpoint = item.isSetpoint ?? false;
    final icon = item.icon ?? (isSetpoint ? '🎯' : '🌡️');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      color: isSetpoint
          ? (isDark ? Colors.blue[900]?.withOpacity(0.3) : Colors.blue[50])
          : ThemeUtils.cardColor(context),
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
                      color: isSetpoint
                          ? (isDark ? Colors.blue[300] : Colors.blue[800])
                          : ThemeUtils.textColor(context),
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
                      color: isDark ? Colors.blue[800] : Colors.blue[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'УСТАВКА',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white : Colors.blue[800],
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
                    color: ThemeUtils.getSensorValueColor(
                      context,
                      value,
                      min: item.min,
                      max: item.max,
                    ),
                  ),
                ),
                Text(
                  item.unit ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    color: isSetpoint
                        ? (isDark ? Colors.blue[300] : Colors.blue[700])
                        : ThemeUtils.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
