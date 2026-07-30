import 'dart:async';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  // Список логов в памяти (последние 5 минут)
  final List<LogEntry> _logs = [];
  static const int MAX_LOG_ENTRIES = 500;

  // Таймер для очистки старых логов
  Timer? _cleanupTimer;

  // Флаг инициализации
  bool _isInitialized = false;

  // Подписка на изменения
  final List<void Function(List<LogEntry>)> _listeners = [];

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void addListener(void Function(List<LogEntry>) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(List<LogEntry>) listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener(_logs);
    }
  }

  // Инициализация
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Запрашиваем разрешение на запись (для Android)
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        print('⚠️ Нет разрешения на запись в хранилище');
      }
    }

    // Запускаем таймер очистки (каждые 10 секунд)
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _cleanupOldLogs();
    });

    print('✅ LoggerService инициализирован');
  }

  // Очистка старых логов
  void _cleanupOldLogs() {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(minutes: 5));

    // Оставляем только логи не старше 5 минут
    _logs.retainWhere((entry) => entry.timestamp.isAfter(cutoff));

    // Если логов слишком много, обрезаем
    if (_logs.length > MAX_LOG_ENTRIES) {
      _logs.removeRange(0, _logs.length - MAX_LOG_ENTRIES);
    }
  }

  // Добавление лога
  void log(String message, {LogLevel level = LogLevel.info}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    );

    _logs.add(entry);

    // Очищаем старые логи при добавлении
    _cleanupOldLogs();

    // Уведомляем слушателей
    _notifyListeners();

    // Выводим в консоль
    print(entry.toString());
  }

  // Очистка всех логов
  Future<void> clearLogs() async {
    _logs.clear();
    _notifyListeners();
  }

  // Получение логов в виде текста
  String getLogsText() {
    return _logs.map((e) => e.toString()).join('\n');
  }

  // Экспорт логов в файл (без path_provider)
  Future<File?> exportLogs() async {
    try {
      // Используем временную директорию
      final tempDir = Directory.systemTemp;
      final exportFile = File(
        '${tempDir.path}/logs_export_${DateTime.now().millisecondsSinceEpoch}.txt',
      );
      await exportFile.writeAsString(getLogsText());
      return exportFile;
    } catch (e) {
      print('⚠️ Ошибка экспорта логов: $e');
      return null;
    }
  }

  // Остановка сервиса
  void dispose() {
    _cleanupTimer?.cancel();
  }
}

// Модель записи лога
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  // Преобразование в строку для сохранения
  @override
  String toString() {
    final timeStr = timestamp.toString().substring(0, 19);
    return '[$timeStr] [${level.name.toUpperCase()}] $message';
  }

  // Создание из строки
  static LogEntry? fromString(String line) {
    try {
      // Формат: [2024-01-01 12:00:00] [INFO] message
      final regex = RegExp(r'\[(.*?)\] \[(.*?)\] (.*)');
      final match = regex.firstMatch(line);
      if (match == null) return null;

      final timestamp = DateTime.parse(match.group(1)!);
      final level = LogLevel.values.firstWhere(
        (e) => e.name == match.group(2)!.toLowerCase(),
        orElse: () => LogLevel.info,
      );
      final message = match.group(3)!;

      return LogEntry(timestamp: timestamp, level: level, message: message);
    } catch (e) {
      return null;
    }
  }
}

// Уровни логирования
enum LogLevel { debug, info, warning, error }
