import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../widgets/relay_widget.dart';
import '../core/utils/theme_utils.dart';

class RelaysListWidget extends StatelessWidget {
  final SubmenuConfig submenu;
  final Map<String, dynamic> realtimeData;

  const RelaysListWidget({
    super.key,
    required this.submenu,
    required this.realtimeData,
  });

  @override
  Widget build(BuildContext context) {
    if (submenu.items == null || submenu.items!.isEmpty) {
      return Container(
        color: ThemeUtils.scaffoldColor(context),
        child: const Center(child: Text('Нет реле')),
      );
    }

    return Container(
      color: ThemeUtils.scaffoldColor(context),
      child: ListView(
        padding: const EdgeInsets.all(16),
        // ✅ Используем ключи для оптимизации
        children: submenu.items!.map((item) {
          final value = realtimeData[item.address.toString()];
          final isOn = value != null && (value & (1 << (item.bit ?? 0))) != 0;

          return RelayWidget(
            item: item,
            value: value,
            key: ValueKey('relay_${item.address}_${isOn}_${value}'),
          );
        }).toList(),
      ),
    );
  }
}
