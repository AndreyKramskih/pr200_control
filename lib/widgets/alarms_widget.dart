// lib/widgets/alarms_widget.dart
import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../models/modbus_data.dart';

/// Виджет для отображения аварий
class AlarmsWidget extends StatelessWidget {
  final SubmenuConfig submenu;
  final List<AlarmItem> alarms;
  final VoidCallback onResetAlarms;
  final bool isResetting;

  const AlarmsWidget({
    super.key,
    required this.submenu,
    required this.alarms,
    required this.onResetAlarms,
    this.isResetting = false,
  });

  @override
  Widget build(BuildContext context) {
    if (alarms.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Аварий нет',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...alarms.map((alarm) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: Colors.red[50],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.red[300]!, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          alarm.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    alarm.description,
                    style: TextStyle(color: Colors.red[700]),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
        const SizedBox(height: 16),
        if (submenu.resetAddress != null)
          ElevatedButton.icon(
            onPressed: isResetting ? null : onResetAlarms,
            icon: isResetting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(isResetting ? 'Сброс...' : 'Сбросить аварии'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
      ],
    );
  }
}
