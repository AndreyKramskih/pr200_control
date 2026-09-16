/// Базовое исключение приложения
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  AppException(this.message, {this.code, this.originalError});

  @override
  String toString() =>
      'AppException: $message${code != null ? ' (code: $code)' : ''}';
}

/// Ошибка подключения к Modbus
class ModbusConnectionException extends AppException {
  ModbusConnectionException(super.message, {super.originalError})
    : super(
        code: 'MODBUS_CONNECTION_ERROR',
      );
}

/// Ошибка чтения Modbus
class ModbusReadException extends AppException {
  ModbusReadException(super.message, {super.originalError})
    : super(code: 'MODBUS_READ_ERROR');
}

/// Ошибка записи Modbus
class ModbusWriteException extends AppException {
  ModbusWriteException(super.message, {super.originalError})
    : super(code: 'MODBUS_WRITE_ERROR');
}

/// Ошибка валидации
class ValidationException extends AppException {
  ValidationException(super.message, {super.originalError})
    : super(code: 'VALIDATION_ERROR');
}

/// Ошибка конфигурации
class ConfigException extends AppException {
  ConfigException(super.message, {super.originalError})
    : super(code: 'CONFIG_ERROR');
}
