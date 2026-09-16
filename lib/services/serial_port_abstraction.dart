// lib/services/serial_port_abstraction.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'serial_port_android.dart';
import 'serial_port_desktop.dart';

/// Универсальное описание устройства
class SerialDeviceInfo {
  final String deviceName; // путь или имя для подключения
  final String displayName; // человекочитаемое имя
  SerialDeviceInfo({required this.deviceName, required this.displayName});
}

/// Абстракция последовательного порта.
/// Реализации: AndroidSerialPort, WindowsSerialPort.
abstract class SerialPortAdapter {
  /// Список доступных портов
  Future<List<SerialDeviceInfo>> getAvailableDevices();

  /// Подключиться к порту
  Future<bool> connect(SerialDeviceInfo device, int baudRate);

  /// Отправить байты
  Future<bool> write(Uint8List data);

  /// Поток входящих данных
  Stream<List<int>> get dataStream;

  /// Поток событий подключения (true — подключено, false — потеряно)
  Stream<bool> get connectionStream;

  /// Отключиться
  Future<void> disconnect();
}

/// Фабрика — выбирает реализацию по платформе
class SerialPortFactory {
  static SerialPortAdapter create() {
    if (Platform.isAndroid) {
      return AndroidSerialPortAdapter();
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return DesktopSerialPortAdapter();
    }
    throw UnsupportedError('Платформа не поддерживается');
  }
}
