import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../widgets/sensor_widget.dart';
import '../core/utils/theme_utils.dart';

class SensorsListWidget extends StatelessWidget {
  final SubmenuConfig submenu;
  final Map<String, dynamic> realtimeData;

  const SensorsListWidget({
    super.key,
    required this.submenu,
    required this.realtimeData,
  });

  @override
  Widget build(BuildContext context) {
    if (submenu.items == null || submenu.items!.isEmpty) {
      return Container(
        color: ThemeUtils.scaffoldColor(context),
        child: const Center(child: Text('Нет датчиков')),
      );
    }

    return Container(
      color: ThemeUtils.scaffoldColor(context),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: submenu.items!.map((item) {
          final value = realtimeData[item.address.toString()];
          return SensorWidget(
            item: item,
            value: value,
            key: ValueKey('sensor_${item.address}'),
          );
        }).toList(),
      ),
    );
  }
}
