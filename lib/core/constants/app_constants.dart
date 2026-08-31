/// Глобальные константы приложения
class AppConstants {
  // Modbus
  static const int DEFAULT_PORT = 502;
  static const int DEFAULT_SLAVE_ID = 1;
  static const int DEFAULT_TIMEOUT_SECONDS = 3;
  static const int DEFAULT_RETRIES = 3;

  // RTU
  static const int DEFAULT_BAUD_RATE = 115200;

  // БИТЫ
  static const int MAX_REGISTERS_PER_REQUEST = 12;

  // Логи
  static const int MAX_LOG_ENTRIES = 500;
  static const Duration LOG_CLEANUP_INTERVAL = Duration(seconds: 10);
  static const Duration LOG_RETENTION = Duration(minutes: 5);

  // Обновление данных
  static const Duration UPDATE_INTERVAL = Duration(seconds: 1);

  // Параметры
  static const int MAX_TREND_POINTS = 60;
}
