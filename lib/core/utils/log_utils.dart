import '../../services/logger_service.dart';

/// Утилита для логирования (безопасная обертка)
class LogUtils {
  static void debug(String message) {
    LoggerService().log(message, level: LogLevel.debug);
  }

  static void info(String message) {
    LoggerService().log(message, level: LogLevel.info);
  }

  static void warning(String message) {
    LoggerService().log(message, level: LogLevel.warning);
  }

  static void error(String message) {
    LoggerService().log(message, level: LogLevel.error);
  }
}
