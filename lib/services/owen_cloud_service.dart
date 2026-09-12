// lib/services/owen_cloud_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/config_model.dart';
import '../models/modbus_data.dart';
import 'logger_service.dart';

class OwenCloudService extends ChangeNotifier {
  static const String _baseUrl = 'https://api.owencloud.ru/v1';
  static const Duration _tokenLifetime = Duration(minutes: 20);
  static const Duration _refreshBefore = Duration(minutes: 4);

  // ✅ Owen Cloud: 10 запросов / 10 сек → минимум 1.1 сек между запросами
  static const Duration _minRequestInterval = Duration(milliseconds: 1100);

  // ✅ Кэш значений — 2 секунды (гасит частые обновления от UI)
  static const Duration _valueCacheTtl = Duration(seconds: 2);

  final http.Client _http = http.Client();

  bool _connected = false;
  String _lastError = '';
  String _login = '';
  String _password = '';
  String? _token;
  DateTime? _tokenExpiry;
  int? _deviceId;
  // int _writeGroupId = 0;
  Timer? _tokenTimer;

  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _throttleLock;

  // ✅ Флаг: параметры уже загружаются/загружены — не перезагружать
  bool _loadingParamIds = false;

  final Map<String, int> _paramIdCache = {};
  final Map<int, int> _registerCache = {};
  final Map<int, double> _floatCache = {};

  // ✅ Кэш последних значений с TTL
  final Map<int, _CachedValue> _valueCache = {};

  final List<AlarmItem> _activeAlarms = [];

  // === Геттеры ===
  bool get connected => _connected;
  String get lastError => _lastError;
  Map<int, int> get registerCache => _registerCache;
  Map<String, int> get paramIdCache => Map.unmodifiable(_paramIdCache);
  String? get token => _token;
  int? get deviceId => _deviceId;
  List<AlarmItem> get activeAlarms => _activeAlarms;

  // ==================== ПОДКЛЮЧЕНИЕ ====================

  Future<bool> connect({
    required String login,
    required String password,
    int? deviceId,
    int writeGroupId = 0,
    Map<String, int>? cachedParamIds,
  }) async {
    LoggerService().log('🔵 Owen Cloud: подключение ($login)');

    _login = login;
    _password = password;
    _deviceId = deviceId;
    // _writeGroupId = writeGroupId;

    if (cachedParamIds != null && cachedParamIds.isNotEmpty) {
      _paramIdCache.addAll(cachedParamIds);
    }

    final ok = await _authenticate();
    if (!ok) {
      _connected = false;
      notifyListeners();
      return false;
    }

    // ✅ Загружаем параметры только если кэша нет или он подозрительно мал
    if (_deviceId != null && _deviceId! > 0 && _paramIdCache.isEmpty) {
      await _loadParamIds(_deviceId!);
    }

    _connected = true;
    _lastError = '';
    _startTokenTimer();
    notifyListeners();
    return true;
  }

  // ==================== АУТЕНТИФИКАЦИЯ ====================

  Future<bool> _authenticate() async {
    try {
      await _throttle();
      final response = await _http
          .post(
            Uri.parse('$_baseUrl/auth/open'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'login': _login, 'password': _password}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _lastError = 'HTTP ${response.statusCode}: ${response.body}';
        LoggerService().log(
          '❌ Owen Cloud auth: $_lastError',
          level: LogLevel.error,
        );
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _token = data['token']?.toString();
      if (_token == null || _token!.isEmpty) {
        _lastError = 'Пустой токен в ответе';
        return false;
      }

      _tokenExpiry = DateTime.now().add(_tokenLifetime);
      LoggerService().log('✅ Owen Cloud: токен получен');
      return true;
    } catch (e) {
      _lastError = 'Ошибка авторизации: $e';
      LoggerService().log('❌ Owen Cloud auth: $e', level: LogLevel.error);
      return false;
    }
  }

  void _startTokenTimer() {
    _tokenTimer?.cancel();
    final interval = _tokenLifetime - _refreshBefore;
    _tokenTimer = Timer.periodic(interval, (_) => _refreshTokenIfNeeded());
  }

  Future<void> _refreshTokenIfNeeded() async {
    if (_tokenExpiry == null) return;
    final untilExpiry = _tokenExpiry!.difference(DateTime.now());
    if (untilExpiry <= _refreshBefore) {
      final ok = await _authenticate();
      if (ok) notifyListeners();
    }
  }

  Future<bool> _ensureToken() async {
    if (_token == null || _tokenExpiry == null) {
      return await _authenticate();
    }
    if (DateTime.now().isAfter(_tokenExpiry!)) {
      return await _authenticate();
    }
    if (_tokenExpiry!.difference(DateTime.now()) < const Duration(minutes: 2)) {
      await _authenticate();
    }
    return _token != null;
  }

  // ==================== THROTTLE + RETRY ====================

  /// Гарантирует минимум `_minRequestInterval` между запросами.
  /// Последовательные вызовы ждут своей очереди.
  Future<void> _throttle() async {
    if (_throttleLock != null) {
      await _throttleLock;
    }
    final elapsed = DateTime.now().difference(_lastRequestTime);
    if (elapsed < _minRequestInterval) {
      final completer = Completer<void>();
      _throttleLock = completer.future;
      await Future.delayed(_minRequestInterval - elapsed);
      _lastRequestTime = DateTime.now();
      completer.complete();
      _throttleLock = null;
    } else {
      _lastRequestTime = DateTime.now();
    }
  }

  /// POST с retry при 429.
  Future<http.Response> _postWithRetry(
    Uri uri,
    Map<String, String> headers,
    String body, {
    int maxRetries = 3,
  }) async {
    int attempt = 0;
    while (true) {
      await _throttle();
      final response = await _http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 429 || attempt >= maxRetries) {
        return response;
      }

      attempt++;
      // Уважаем Retry-After, если пришёл
      int waitSec = 2 << (attempt - 1); // 2, 4, 8
      final retryAfter = response.headers['retry-after'];
      if (retryAfter != null) {
        waitSec = int.tryParse(retryAfter) ?? waitSec;
      }
      LoggerService().log(
        '⚠️ Owen Cloud 429, повтор через ${waitSec}с (попытка $attempt)',
        level: LogLevel.warning,
      );
      await Future.delayed(Duration(seconds: waitSec));
    }
  }

  // ==================== СПИСОК УСТРОЙСТВ ====================

  Future<List<Map<String, dynamic>>> getDevices() async {
    if (!await _ensureToken()) return [];

    try {
      final response = await _postWithRetry(
        Uri.parse('$_baseUrl/device/index'),
        _authHeaders,
        jsonEncode({}),
      );

      if (response.statusCode != 200) {
        _lastError = 'device/index: HTTP ${response.statusCode}';
        return [];
      }

      final decoded = jsonDecode(response.body);
      final List<dynamic> rawList;
      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map && decoded['data'] is List) {
        rawList = decoded['data'] as List;
      } else {
        _lastError = 'Неожиданный формат device/index';
        return [];
      }
      return rawList.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      _lastError = 'Ошибка getDevices: $e';
      LoggerService().log(_lastError, level: LogLevel.error);
      return [];
    }
  }

  // ==================== ЗАГРУЗКА ID ПАРАМЕТРОВ ====================

  Future<bool> _loadParamIds(int deviceId) async {
    if (_loadingParamIds) return _paramIdCache.isNotEmpty;
    _loadingParamIds = true;

    try {
      if (!await _ensureToken()) return false;

      final response = await _postWithRetry(
        Uri.parse('$_baseUrl/device/$deviceId'),
        _authHeaders,
        jsonEncode({}),
      );

      if (response.statusCode != 200) {
        _lastError = 'device/$deviceId: HTTP ${response.statusCode}';
        LoggerService().log(_lastError, level: LogLevel.warning);
        return false;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final params = decoded['parameters'] as List<dynamic>? ?? [];

      _paramIdCache.clear();
      for (final p in params) {
        if (p is! Map) continue;
        final id = p['id'];
        final code = p['code']?.toString();
        if (id is int && code != null && code.isNotEmpty) {
          // ✅ Универсальный ключ: убираем все символы кроме цифр
          final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
          if (digits.isNotEmpty) {
            _paramIdCache[digits] = id;
          }
        }
      }

      LoggerService().log(
        '✅ Owen Cloud: загружено ${_paramIdCache.length} параметров',
      );
      notifyListeners();
      return _paramIdCache.isNotEmpty;
    } catch (e) {
      _lastError = 'Ошибка загрузки параметров: $e';
      LoggerService().log(_lastError, level: LogLevel.error);
      return false;
    } finally {
      _loadingParamIds = false;
    }
  }

  Future<bool> refreshParamIds() async {
    if (_deviceId == null) return false;
    return await _loadParamIds(_deviceId!);
  }

  // ==================== АДРЕС → ID ====================

  /// Modbus-адрес → ключ кэша (только цифры)
  String _addressKey(int address) => address.toString();

  int? _addressToId(int address) => _paramIdCache[_addressKey(address)];

  // ==================== ЧТЕНИЕ ====================

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_token',
  };

  bool _isCacheValid(int address) {
    final c = _valueCache[address];
    if (c == null) return false;
    return DateTime.now().difference(c.ts) < _valueCacheTtl;
  }

  void _putCache(int address, dynamic value) {
    _valueCache[address] = _CachedValue(value, DateTime.now());
  }

  Future<Map<int, dynamic>> _readRawAddresses(List<int> addresses) async {
    if (!_connected) {
      _lastError = 'Нет подключения';
      final cached = <int, dynamic>{};
      for (final a in addresses) {
        if (_valueCache.containsKey(a)) cached[a] = _valueCache[a]!.value;
      }
      return cached;
    }
    if (!await _ensureToken()) {
      _lastError = 'Не удалось получить токен';
      return {};
    }

    final result = <int, dynamic>{};
    final idToAddress = <int, int>{};
    final ids = <int>[];

    for (final addr in addresses) {
      if (_isCacheValid(addr)) {
        result[addr] = _valueCache[addr]!.value;
      } else {
        final id = _addressToId(addr);
        if (id != null) {
          ids.add(id);
          idToAddress[id] = addr;
        } else {
          LoggerService().log(
            '⚠️ Owen Cloud: нет ID для адреса $addr',
            level: LogLevel.warning,
          );
        }
      }
    }

    if (ids.isEmpty) return result;

    try {
      final response = await _postWithRetry(
        Uri.parse('$_baseUrl/parameters/last-data'),
        _authHeaders,
        jsonEncode({'ids': ids}),
      );

      if (response.statusCode != 200) {
        _lastError = 'last-data: HTTP ${response.statusCode}';
        LoggerService().log(_lastError, level: LogLevel.error);
        return result;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map) continue;
          final id = item['id'];
          if (id is! int) continue;

          final addr = idToAddress[id];
          if (addr == null) continue;

          // values — массив; берём последнее значение
          final values = item['values'];
          if (values is! List || values.isEmpty) continue;
          final last = values.last;
          if (last is! Map) continue;

          // Если пришла ошибка — пропускаем этот параметр
          final err = last['e'];
          if (err != null && err.toString().isNotEmpty) {
            LoggerService().log(
              '⚠️ Owen Cloud: ошибка чтения $id: $err',
              level: LogLevel.warning,
            );
            continue;
          }

          final v = last['v'];
          if (v == null) continue;

          result[addr] = v;
          _putCache(addr, v);
        }
      }

      if (result.isEmpty) {
        LoggerService().log(
          '⚠️ Owen Cloud: last-data вернул 0 значений (получено из ответа ${decoded is List ? decoded.length : "?"})',
          level: LogLevel.warning,
        );
      }

      return result;
    } catch (e) {
      _lastError = 'Ошибка чтения: $e';
      LoggerService().log(_lastError, level: LogLevel.error);
      return result;
    }
  }

  Future<int?> readRegister(
    int address, {
    int count = 1,
    String type = 'int',
  }) async {
    final raw = await _readRawAddresses([address]);
    if (!raw.containsKey(address)) return null;
    final v = raw[address];
    if (type == 'float') return double.tryParse(v.toString())?.toInt();
    final i = int.tryParse(v.toString());
    if (i != null) _registerCache[address] = i;
    return i;
  }

  Future<double?> readFloat(int address) async {
    final raw = await _readRawAddresses([address]);
    if (!raw.containsKey(address)) return null;
    final d = double.tryParse(raw[address].toString());
    if (d != null) _floatCache[address] = d;
    return d;
  }

  Future<Map<int, int>> readMultipleRegisters(List<int> addresses) async {
    final raw = await _readRawAddresses(addresses);
    final result = <int, int>{};
    raw.forEach((addr, v) {
      final i = int.tryParse(v.toString());
      if (i != null) {
        result[addr] = i;
        _registerCache[addr] = i;
      }
    });
    return result;
  }

  Future<Map<int, double>> readMultipleFloats(List<int> addresses) async {
    final raw = await _readRawAddresses(addresses);
    final result = <int, double>{};
    raw.forEach((addr, v) {
      final d = double.tryParse(v.toString());
      if (d != null) {
        result[addr] = d;
        _floatCache[addr] = d;
      }
    });
    return result;
  }

  Future<dynamic> readParameterValue(ItemConfig param) async {
    final raw = await _readRawAddresses([param.address]);
    if (!raw.containsKey(param.address)) return null;
    final v = raw[param.address];
    if (param.type == 'float') return double.tryParse(v.toString());
    return int.tryParse(v.toString());
  }

  // ==================== ЗАПИСЬ ====================

  Future<bool> writeRegister(
    int address,
    dynamic value, {
    String type = 'int',
  }) async {
    if (!_connected) {
      _lastError = 'Нет подключения';
      return false;
    }
    if (!await _ensureToken()) {
      _lastError = 'Не удалось получить токен';
      return false;
    }

    final paramId = _addressToId(address);
    if (paramId == null) {
      _lastError = 'Нет ID для адреса $address';
      return false;
    }

    try {
      final response = await _postWithRetry(
        Uri.parse('$_baseUrl/parameters/write-data'),
        _authHeaders,
        jsonEncode({
          'data': [
            {'id': paramId, 'value': value.toString()},
          ],
        }),
      );

      if (response.statusCode != 200) {
        _lastError = 'write-data: HTTP ${response.statusCode} ${response.body}';
        LoggerService().log(_lastError, level: LogLevel.error);
        return false;
      }

      _registerCache.remove(address);
      _floatCache.remove(address);
      _valueCache.remove(address);
      LoggerService().log('✅ Owen Cloud: запись $address = $value');
      return true;
    } catch (e) {
      _lastError = 'Ошибка записи: $e';
      LoggerService().log(_lastError, level: LogLevel.error);
      return false;
    }
  }

  Future<bool> writeFloat(int address, double value) async {
    return await writeRegister(address, value, type: 'float');
  }

  Future<bool> writeMultipleRegisters(
    Map<int, dynamic> values, {
    String type = 'int',
  }) async {
    if (!await _ensureToken()) return false;

    final writeParams = <Map<String, dynamic>>[];
    for (final entry in values.entries) {
      final id = _addressToId(entry.key);
      if (id == null) continue;
      writeParams.add({'id': id, 'value': entry.value.toString()});
    }

    if (writeParams.isEmpty) {
      _lastError = 'Нет валидных ID для записи';
      return false;
    }

    try {
      final response = await _postWithRetry(
        Uri.parse('$_baseUrl/parameters/write-data'),
        _authHeaders,
        jsonEncode({'data': writeParams}),
      );
      if (response.statusCode != 200) {
        _lastError = 'write-data: HTTP ${response.statusCode}';
        return false;
      }
      for (final addr in values.keys) {
        _registerCache.remove(addr);
        _floatCache.remove(addr);
        _valueCache.remove(addr);
      }
      return true;
    } catch (e) {
      _lastError = 'Ошибка batch-записи: $e';
      return false;
    }
  }
  // ==================== АВАРИИ ====================

  Future<List<AlarmItem>> readAlarms(
    int address,
    List<AlarmConfig> alarms,
  ) async {
    final raw = await _readRawAddresses([address]);
    if (!raw.containsKey(address)) return [];

    final value = int.tryParse(raw[address].toString());
    if (value == null) return [];

    final active = <AlarmItem>[];
    for (final alarm in alarms) {
      if ((value & (1 << alarm.bit)) != 0) {
        active.add(
          AlarmItem(
            name: alarm.name,
            description: alarm.description,
            address: alarm.address,
            bit: alarm.bit,
          ),
        );
      }
    }
    _activeAlarms
      ..clear()
      ..addAll(active);
    return active;
  }

  // ==================== PING ====================

  Future<bool> ping() async {
    if (!await _ensureToken()) return false;
    try {
      final response = await _postWithRetry(
        Uri.parse('$_baseUrl/device/index'),
        _authHeaders,
        jsonEncode({}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ==================== ОТКЛЮЧЕНИЕ ====================

  Future<void> disconnect() async {
    _tokenTimer?.cancel();
    _tokenTimer = null;
    _connected = false;
    _token = null;
    _tokenExpiry = null;
    _registerCache.clear();
    _floatCache.clear();
    _valueCache.clear();
    _activeAlarms.clear();
    LoggerService().log('🔌 Owen Cloud: отключено');
    notifyListeners();
  }

  @override
  void dispose() {
    _tokenTimer?.cancel();
    _http.close();
    super.dispose();
  }
}

class _CachedValue {
  final dynamic value;
  final DateTime ts;
  _CachedValue(this.value, this.ts);
}
