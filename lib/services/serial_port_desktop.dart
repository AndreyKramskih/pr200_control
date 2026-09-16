// lib/services/serial_port_desktop.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_port_abstraction.dart';
import 'logger_service.dart';

/// Реализация для Windows/Linux/macOS через flutter_libserialport
class DesktopSerialPortAdapter implements SerialPortAdapter {
  SerialPort? _port;
  StreamSubscription? _readSub;
  Timer? _readTimer;

  final _dataController = StreamController<List<int>>.broadcast();
  final _connController = StreamController<bool>.broadcast();

  @override
  Stream<List<int>> get dataStream => _dataController.stream;

  @override
  Stream<bool> get connectionStream => _connController.stream;

  @override
  Future<List<SerialDeviceInfo>> getAvailableDevices() async {
    try {
      final ports = SerialPort.availablePorts; // например ["COM3", "COM4"]
      return ports
          .map((p) => SerialDeviceInfo(deviceName: p, displayName: p))
          .toList();
    } catch (e) {
      LoggerService().log(
        '❌ Desktop getAvailableDevices: $e',
        level: LogLevel.error,
      );
      return [];
    }
  }

  @override
  Future<bool> connect(SerialDeviceInfo device, int baudRate) async {
    try {
      // Закрываем предыдущее соединение
      await disconnect();

      final port = SerialPort(device.deviceName);
      if (!port.openReadWrite()) {
        LoggerService().log(
          '❌ Не удалось открыть ${device.deviceName}: ${SerialPort.lastError}',
          level: LogLevel.error,
        );
        return false;
      }

      final config = port.config;
      config.baudRate = baudRate;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;

      try {
        port.config = config;
      } catch (e) {
        LoggerService().log(
          '❌ Ошибка настройки порта: $e',
          level: LogLevel.error,
        );
        port.close();
        return false;
      }

      _port = port;
      _startReading();
      _connController.add(true);
      LoggerService().log(
        '✅ Desktop RTU открыт: ${device.deviceName} @ $baudRate',
      );
      return true;
    } catch (e) {
      LoggerService().log('❌ Desktop connect: $e', level: LogLevel.error);
      return false;
    }
  }

  void _startReading() {
    _readTimer?.cancel();
    _readTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final port = _port;
      if (port == null || !port.isOpen) {
        _connController.add(false);
        _readTimer?.cancel();
        return;
      }
      try {
        final available = port.bytesAvailable;
        if (available > 0) {
          final data = port.read(available);
          if (data.isNotEmpty) {
            _dataController.add(data);
          }
        }
      } catch (e) {
        LoggerService().log('❌ Desktop read: $e', level: LogLevel.error);
        _connController.add(false);
      }
    });
  }

  @override
  Future<bool> write(Uint8List data) async {
    final port = _port;
    if (port == null || !port.isOpen) return false;
    try {
      final written = port.write(data, timeout: 1000);
      return written == data.length;
    } catch (e) {
      LoggerService().log('❌ Desktop write: $e', level: LogLevel.error);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _readTimer?.cancel();
    _readTimer = null;
    _readSub?.cancel();
    _readSub = null;
    try {
      _port?.close();
    } catch (_) {}
    _port = null;
  }
}
