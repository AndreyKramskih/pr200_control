/// Глобальные константы приложения
class AppConstants {
  // Modbus
  static const int defaultPort = 502;
  static const int defaultSlaveId = 1;
  static const int defaultTimeoutSeconds = 3;
  static const int defaultRetries = 3;

  // RTU
  static const int defaultBaudRate = 115200;

  // БИТЫ
  static const int maxRegistersPerRequest = 12;

  // Логи
  static const int maxLogEntries = 500;
  static const Duration logCleanupInterval = Duration(seconds: 10);
  static const Duration logRetention = Duration(minutes: 5);

  // Обновление данных
  static const Duration updateInterval = Duration(seconds: 1);

  // Параметры
  static const int maxTrendPoints = 60;
}
