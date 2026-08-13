import 'dart:async';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants/app_constants.dart';

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  final List<LogEntry> _logs = [];
  Timer? _cleanupTimer;
  bool _isInitialized = false;
  final List<void Function(List<LogEntry>)> _listeners = [];

  // ✅ Минимальный уровень для фильтрации
  LogLevel _minLevel = LogLevel.debug;

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void setMinLevel(LogLevel level) {
    _minLevel = level;
    _notifyListeners();
  }

  LogLevel get minLevel => _minLevel;

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

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        log('⚠️ Нет разрешения на запись в хранилище', level: LogLevel.warning);
      }
    }

    _cleanupTimer = Timer.periodic(AppConstants.LOG_CLEANUP_INTERVAL, (_) {
      _cleanupOldLogs();
    });

    log('✅ LoggerService инициализирован', level: LogLevel.info);
  }

  void _cleanupOldLogs() {
    final now = DateTime.now();
    final cutoff = now.subtract(AppConstants.LOG_RETENTION);

    _logs.retainWhere((entry) => entry.timestamp.isAfter(cutoff));

    if (_logs.length > AppConstants.MAX_LOG_ENTRIES) {
      _logs.removeRange(0, _logs.length - AppConstants.MAX_LOG_ENTRIES);
    }
  }

  void log(String message, {LogLevel level = LogLevel.info}) {
    // ✅ Фильтрация по уровню
    if (level.index < _minLevel.index) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    );

    _logs.add(entry);
    _cleanupOldLogs();
    _notifyListeners();

    // ✅ Всегда выводим в консоль для отладки
    print(entry.toString());
  }

  Future<void> clearLogs() async {
    _logs.clear();
    _notifyListeners();
  }

  String getLogsText() {
    return _logs.map((e) => e.toString()).join('\n');
  }

  // ✅ Метод для получения логов с фильтром
  List<LogEntry> getFilteredLogs({LogLevel? minLevel}) {
    final level = minLevel ?? _minLevel;
    return _logs.where((log) => log.level.index >= level.index).toList();
  }

  // ✅ Метод для замера времени выполнения
  Future<T> timed<T>(
    String operationName,
    Future<T> Function() operation,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await operation();
      stopwatch.stop();
      log(
        '⏱️ $operationName выполнено за ${stopwatch.elapsedMilliseconds}мс',
        level: LogLevel.debug,
      );
      return result;
    } catch (e) {
      stopwatch.stop();
      log(
        '❌ $operationName завершилось ошибкой после ${stopwatch.elapsedMilliseconds}мс: $e',
        level: LogLevel.error,
      );
      rethrow;
    }
  }

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

  @override
  String toString() {
    final timeStr = timestamp.toString().substring(0, 19);
    return '[$timeStr] [${level.name.toUpperCase()}] $message';
  }

  static LogEntry? fromString(String line) {
    try {
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

enum LogLevel { debug, info, warning, error }
