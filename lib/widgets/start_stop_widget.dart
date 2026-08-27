import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../core/utils/theme_utils.dart';

class StartStopWidget extends StatelessWidget {
  final SubmenuConfig submenu;
  final Map<String, dynamic> realtimeData;
  final VoidCallback onToggle;

  const StartStopWidget({
    super.key,
    required this.submenu,
    required this.realtimeData,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeUtils.isDark(context);

    if (submenu.items == null || submenu.items!.isEmpty) {
      return Container(
        color: ThemeUtils.scaffoldColor(context),
        child: const Center(child: Text('Нет элементов управления')),
      );
    }

    final item = submenu.items!.first;
    final value = realtimeData[item.address.toString()];
    final isOn = value != null && (value & (1 << (item.bit ?? 0))) != 0;

    return Container(
      color: ThemeUtils.scaffoldColor(context),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOn
                      ? (isDark
                            ? Colors.green[800]?.withOpacity(0.5)
                            : Colors.green[100])
                      : (isDark
                            ? Colors.red[800]?.withOpacity(0.5)
                            : Colors.red[100]),
                  border: Border.all(
                    color: isOn ? Colors.green : Colors.red,
                    width: 4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isOn ? Colors.green : Colors.red).withOpacity(
                        0.3,
                      ),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  isOn ? Icons.power_settings_new : Icons.power_off,
                  size: 60,
                  color: isOn ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                item.name,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: ThemeUtils.textColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isOn ? 'Включено' : 'Выключено',
                style: TextStyle(
                  fontSize: 18,
                  color: isOn ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 200,
                child: ElevatedButton(
                  onPressed: onToggle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isOn ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isOn ? 'Выключить' : 'Включить',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
