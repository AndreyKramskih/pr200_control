// lib/services/pin_service.dart
import 'dart:io';
//import 'package:flutter/services.dart';
import '../core/exceptions/app_exceptions.dart';
import 'logger_service.dart';

/// Сервис для управления PIN-кодом
class PinService {
  static final PinService _instance = PinService._internal();
  factory PinService() => _instance;
  PinService._internal();

  static const String _pinFileName = 'pin_code.txt';
  static const int MAX_ATTEMPTS = 3;
  static const Duration LOCKOUT_DURATION = Duration(minutes: 5);

  String? _cachedPin;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  bool get isLocked =>
      _lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!);
  int get remainingAttempts => MAX_ATTEMPTS - _failedAttempts;
  DateTime? get lockoutUntil => _lockoutUntil;

  /// Получить директорию для хранения
  Future<String> _getAppDirectory() async {
    if (Platform.isAndroid) {
      final externalDir =
          '/storage/emulated/0/Android/data/com.example.pr200_control/files';
      try {
        final dir = Directory(externalDir);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return externalDir;
      } catch (e) {
        return '/data/data/com.example.pr200_control/files';
      }
    } else {
      return Directory.current.path;
    }
  }

  /// Установить PIN-код
  Future<void> setPin(String pin) async {
    if (pin.length < 4 || pin.length > 8) {
      throw ValidationException('PIN-код должен содержать от 4 до 8 цифр');
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      throw ValidationException('PIN-код должен содержать только цифры');
    }

    final appDir = await _getAppDirectory();
    final file = File('$appDir/$_pinFileName');

    final hashed = _hashPin(pin);
    await file.writeAsString(hashed);
    _cachedPin = hashed;
    _failedAttempts = 0;
    _lockoutUntil = null;

    LoggerService().log('✅ PIN-код установлен', level: LogLevel.info);
  }

  /// Проверить PIN-код
  Future<bool> verifyPin(String pin) async {
    if (isLocked) {
      final remaining = _lockoutUntil!.difference(DateTime.now());
      LoggerService().log(
        '🔒 Устройство заблокировано на ${remaining.inMinutes} минут',
        level: LogLevel.warning,
      );
      return false;
    }

    final storedPin = await _getStoredPin();
    if (storedPin == null) {
      // PIN не установлен
      return true;
    }

    final hashed = _hashPin(pin);
    final isValid = hashed == storedPin;

    if (!isValid) {
      _failedAttempts++;
      LoggerService().log(
        '❌ Неверный PIN-код (попытка $_failedAttempts из $MAX_ATTEMPTS)',
        level: LogLevel.warning,
      );

      if (_failedAttempts >= MAX_ATTEMPTS) {
        _lockoutUntil = DateTime.now().add(LOCKOUT_DURATION);
        LoggerService().log(
          '🔒 Превышено число попыток, блокировка на ${LOCKOUT_DURATION.inMinutes} минут',
          level: LogLevel.warning,
        );
      }
      return false;
    }

    // Успешная проверка
    _failedAttempts = 0;
    _lockoutUntil = null;
    return true;
  }

  /// Проверить, установлен ли PIN
  Future<bool> isPinSet() async {
    final stored = await _getStoredPin();
    return stored != null;
  }

  /// Удалить PIN-код
  Future<void> removePin() async {
    final appDir = await _getAppDirectory();
    final file = File('$appDir/$_pinFileName');
    if (await file.exists()) {
      await file.delete();
      _cachedPin = null;
      _failedAttempts = 0;
      _lockoutUntil = null;
      LoggerService().log('✅ PIN-код удален', level: LogLevel.info);
    }
  }

  /// Получить сохраненный PIN
  Future<String?> _getStoredPin() async {
    if (_cachedPin != null) return _cachedPin;

    try {
      final appDir = await _getAppDirectory();
      final file = File('$appDir/$_pinFileName');
      if (!await file.exists()) return null;

      _cachedPin = await file.readAsString();
      return _cachedPin;
    } catch (e) {
      LoggerService().log(
        '⚠️ Ошибка чтения PIN-кода: $e',
        level: LogLevel.warning,
      );
      return null;
    }
  }

  /// Хеширование PIN-кода
  String _hashPin(String pin) {
    return pin.split('').map((c) => c.codeUnitAt(0).toRadixString(16)).join();
  }

  /// Сбросить состояние блокировки
  void resetLockout() {
    _failedAttempts = 0;
    _lockoutUntil = null;
  }
}
