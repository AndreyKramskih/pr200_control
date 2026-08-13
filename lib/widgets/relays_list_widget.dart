// lib/widgets/relays_list_widget.dart
import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../widgets/relay_widget.dart';

/// Виджет для отображения списка реле
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
      return const Center(child: Text('Нет реле'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: submenu.items!.map((item) {
        final value = realtimeData[item.address.toString()];
        return RelayWidget(
          item: item,
          value: value,
          key: ValueKey('relay_${item.address}'),
        );
      }).toList(),
    );
  }
}
