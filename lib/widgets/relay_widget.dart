import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../core/utils/theme_utils.dart';

class RelayWidget extends StatelessWidget {
  final ItemConfig item;
  final dynamic value;

  const RelayWidget({super.key, required this.item, this.value});

  @override
  Widget build(BuildContext context) {
    final isOn = value != null && (value & (1 << (item.bit ?? 0))) != 0;

    final stateText = item.states != null && item.states!.isNotEmpty
        ? (isOn ? item.states![1] : item.states![0])
        : (isOn ? 'Вкл' : 'Выкл');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      color: ThemeUtils.cardColor(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOn ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                item.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: ThemeUtils.textColor(context),
                ),
              ),
            ),
            // ✅ Используем ValueKey для предотвращения лишних перестроек
            Text(
              stateText,
              key: ValueKey('${item.address}_${isOn}'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isOn ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
