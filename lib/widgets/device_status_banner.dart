// lib/widgets/device_status_banner.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/config_model.dart';
import '../services/owen_cloud_service.dart';

/// Баннер "Прибор не на связи" для Owen Cloud.
/// Определяет статус по времени последнего полученного значения.
class DeviceStatusBanner extends StatefulWidget {
  const DeviceStatusBanner({super.key});

  @override
  State<DeviceStatusBanner> createState() => _DeviceStatusBannerState();
}

class _DeviceStatusBannerState extends State<DeviceStatusBanner> {
  Timer? _timer;
  final DateTime _createdAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.'
      '${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final config = Provider.of<ConfigModel>(context, listen: false);
    final cloud = Provider.of<OwenCloudService>(context, listen: false);

    // Баннер только для Owen Cloud
    if (config.connectionType != 'cloud') return const SizedBox.shrink();
    if (!cloud.connected) return const SizedBox.shrink();

    // ✅ Grace period: первые 10 секунд жизни виджета баннер не показываем.
    // За это время приложение успевает сделать первый HTTP-запрос
    // и обновить lastDataTimestamp.
    final sinceCreated = DateTime.now().difference(_createdAt);
    if (sinceCreated < const Duration(seconds: 10)) {
      return const SizedBox.shrink();
    }

    final lastTs = cloud.lastDataTimestamp;
    if (lastTs == null) return const SizedBox.shrink();

    // Считаем, что прибор offline, если данные старше 2 минут
    final age = DateTime.now().difference(lastTs);
    if (age < const Duration(minutes: 2)) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.orange[700],
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Прибор не на связи',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Данные от ${_fmt(lastTs)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
