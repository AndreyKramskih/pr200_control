/// Конфигурация подключения к Owen Cloud
class OwenCloudConfig {
  String login;
  String password;
  String? token;
  DateTime? tokenExpiry;
  int? deviceId;
  String? deviceName;
  int writeGroupId;
  Map<String, int> paramIdCache; // "P512" -> 1099136

  OwenCloudConfig({
    this.login = '',
    this.password = '',
    this.token,
    this.tokenExpiry,
    this.deviceId,
    this.deviceName,
    this.writeGroupId = 0,
    Map<String, int>? paramIdCache,
  }) : paramIdCache = paramIdCache ?? {};

  factory OwenCloudConfig.fromJson(Map<String, dynamic> json) {
    final cacheRaw = json['param_id_cache'] as Map<String, dynamic>?;
    final cache = <String, int>{};
    if (cacheRaw != null) {
      cacheRaw.forEach((k, v) {
        final intVal = v is int ? v : int.tryParse(v.toString());
        if (intVal != null) cache[k] = intVal;
      });
    }

    return OwenCloudConfig(
      login: json['login']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      token: json['token']?.toString(),
      tokenExpiry: json['token_expiry'] != null
          ? DateTime.tryParse(json['token_expiry'].toString())
          : null,
      deviceId: json['device_id'] is int
          ? json['device_id'] as int
          : int.tryParse(json['device_id']?.toString() ?? ''),
      deviceName: json['device_name']?.toString(),
      writeGroupId: json['write_group_id'] is int
          ? json['write_group_id'] as int
          : int.tryParse(json['write_group_id']?.toString() ?? '0') ?? 0,
      paramIdCache: cache,
    );
  }

  Map<String, dynamic> toJson() => {
    'login': login,
    'password': password,
    if (token != null) 'token': token,
    if (tokenExpiry != null) 'token_expiry': tokenExpiry!.toIso8601String(),
    if (deviceId != null) 'device_id': deviceId,
    if (deviceName != null) 'device_name': deviceName,
    'write_group_id': writeGroupId,
    'param_id_cache': paramIdCache,
  };

  OwenCloudConfig copyWith({
    String? login,
    String? password,
    String? token,
    DateTime? tokenExpiry,
    int? deviceId,
    String? deviceName,
    int? writeGroupId,
    Map<String, int>? paramIdCache,
  }) {
    return OwenCloudConfig(
      login: login ?? this.login,
      password: password ?? this.password,
      token: token ?? this.token,
      tokenExpiry: tokenExpiry ?? this.tokenExpiry,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      writeGroupId: writeGroupId ?? this.writeGroupId,
      paramIdCache: paramIdCache ?? this.paramIdCache,
    );
  }

  bool get hasCredentials => login.isNotEmpty && password.isNotEmpty;
  bool get hasDevice => deviceId != null && deviceId! > 0;
}
