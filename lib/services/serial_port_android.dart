// lib/services/serial_port_android.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';
import 'package:flutter_serial_communication/models/device_info.dart' as sci;
import 'serial_port_abstraction.dart';
import 'logger_service.dart';

class AndroidSerialPortAdapter implements SerialPortAdapter {
  final FlutterSerialCommunication _serialComm = FlutterSerialCommunication();
  StreamSubscription? _messageSub;
  StreamSubscription? _connSub;

  final _dataController = StreamController<List<int>>.broadcast();
  final _connController = StreamController<bool>.broadcast();

  @override
  Stream<List<int>> get dataStream => _dataController.stream;

  @override
  Stream<bool> get connectionStream => _connController.stream;

  @override
  Future<List<SerialDeviceInfo>> getAvailableDevices() async {
    try {
      final devices = await _serialComm.getAvailableDevices();
      return devices
          .map(
            (sci.DeviceInfo d) => SerialDeviceInfo(
              deviceName: d.deviceName,
              displayName: d.deviceName,
            ),
          )
          .toList();
    } catch (e) {
      LoggerService().log(
        '❌ Android getAvailableDevices: $e',
        level: LogLevel.error,
      );
      return [];
    }
  }

  @override
  Future<bool> connect(SerialDeviceInfo device, int baudRate) async {
    try {
      final devices = await _serialComm.getAvailableDevices();
      sci.DeviceInfo? target;
      for (final d in devices) {
        if (d.deviceName == device.deviceName) {
          target = d;
          break;
        }
      }
      target ??= devices.isNotEmpty ? devices.first : null;
      if (target == null) return false;

      final ok = await _serialComm.connect(target, baudRate);
      if (!ok) return false;

      _messageSub?.cancel();
      _connSub?.cancel();

      _messageSub = _serialComm
          .getSerialMessageListener()
          .receiveBroadcastStream()
          .listen(
            (event) {
              if (event is List<int>) _dataController.add(event);
            },
            onError: (e) {
              LoggerService().log(
                '❌ Android data stream: $e',
                level: LogLevel.error,
              );
            },
          );

      _connSub = _serialComm
          .getDeviceConnectionListener()
          .receiveBroadcastStream()
          .listen((event) {
            if (event is bool) _connController.add(event);
          });

      return true;
    } catch (e) {
      LoggerService().log('❌ Android connect: $e', level: LogLevel.error);
      return false;
    }
  }

  @override
  Future<bool> write(Uint8List data) async {
    try {
      return await _serialComm.write(data);
    } catch (e) {
      LoggerService().log('❌ Android write: $e', level: LogLevel.error);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    await _messageSub?.cancel();
    await _connSub?.cancel();
    try {
      await _serialComm.disconnect();
    } catch (_) {}
  }
}
