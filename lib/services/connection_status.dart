// lib/services/connection_status.dart
import 'package:flutter/material.dart';
// import '../models/config_model.dart';
// import 'modbus_service.dart';
// import 'modbus_rtu_service.dart';
// import 'owen_cloud_service.dart';

/// Единый активный канал связи.
enum ActiveChannel { none, tcp, rtu, cloud }

extension ActiveChannelX on ActiveChannel {
  String get label {
    switch (this) {
      case ActiveChannel.tcp:
        return 'TCP/IP';
      case ActiveChannel.rtu:
        return 'RTU (USB)';
      case ActiveChannel.cloud:
        return 'Owen Cloud';
      case ActiveChannel.none:
        return 'Не подключено';
    }
  }

  IconData get icon {
    switch (this) {
      case ActiveChannel.tcp:
        return Icons.settings_ethernet;
      case ActiveChannel.rtu:
        return Icons.usb;
      case ActiveChannel.cloud:
        return Icons.cloud;
      case ActiveChannel.none:
        return Icons.wifi_off;
    }
  }

  Color get color {
    switch (this) {
      case ActiveChannel.tcp:
      case ActiveChannel.rtu:
      case ActiveChannel.cloud:
        return Colors.green;
      case ActiveChannel.none:
        return Colors.red;
    }
  }
}
