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
  ModbusConnectionException(String message, {dynamic originalError})
    : super(
        message,
        code: 'MODBUS_CONNECTION_ERROR',
        originalError: originalError,
      );
}

/// Ошибка чтения Modbus
class ModbusReadException extends AppException {
  ModbusReadException(String message, {dynamic originalError})
    : super(message, code: 'MODBUS_READ_ERROR', originalError: originalError);
}

/// Ошибка записи Modbus
class ModbusWriteException extends AppException {
  ModbusWriteException(String message, {dynamic originalError})
    : super(message, code: 'MODBUS_WRITE_ERROR', originalError: originalError);
}

/// Ошибка валидации
class ValidationException extends AppException {
  ValidationException(String message, {dynamic originalError})
    : super(message, code: 'VALIDATION_ERROR', originalError: originalError);
}

/// Ошибка конфигурации
class ConfigException extends AppException {
  ConfigException(String message, {dynamic originalError})
    : super(message, code: 'CONFIG_ERROR', originalError: originalError);
}
