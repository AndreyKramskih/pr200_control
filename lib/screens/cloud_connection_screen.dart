// lib/screens/cloud_connection_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/config_model.dart';
import '../models/owen_cloud_config.dart';
import '../services/owen_cloud_service.dart';
import '../services/config_service.dart';
import '../services/config_manager.dart';
import '../services/logger_service.dart';
import '../services/modbus_rtu_service.dart';
import '../services/modbus_service.dart';

class CloudConnectionScreen extends StatefulWidget {
  const CloudConnectionScreen({super.key});

  @override
  State<CloudConnectionScreen> createState() => _CloudConnectionScreenState();
}

class _CloudConnectionScreenState extends State<CloudConnectionScreen> {
  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _deviceIdCtrl = TextEditingController();

  bool _obscure = true;
  bool _loadingDevices = false;
  bool _connecting = false;
  bool _saving = false;
  String _status = '';
  Color _statusColor = Colors.grey;

  List<Map<String, dynamic>> _devices = [];
  Map<String, dynamic>? _selectedDevice;

  @override
  void initState() {
    super.initState();
    final config = Provider.of<ConfigModel>(context, listen: false);
    final cloud = config.cloudConfig;
    if (cloud != null) {
      _loginCtrl.text = cloud.login;
      _passCtrl.text = cloud.password;
      _deviceIdCtrl.text = cloud.deviceId?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passCtrl.dispose();
    _deviceIdCtrl.dispose();
    super.dispose();
  }

  // ===== Шаг 1. Авторизация и загрузка списка устройств =====
  Future<void> _loadDevices() async {
    final login = _loginCtrl.text.trim();
    final pass = _passCtrl.text;

    if (login.isEmpty || pass.isEmpty) {
      _setStatus('❌ Введите логин и пароль', Colors.red);
      return;
    }

    setState(() {
      _loadingDevices = true;
      _status = '⏳ Авторизация и загрузка устройств...';
      _statusColor = Colors.orange;
    });

    final service = Provider.of<OwenCloudService>(context, listen: false);

    // Подключаемся без deviceId только ради авторизации
    final ok = await service.connect(login: login, password: pass);

    if (!ok) {
      setState(() {
        _loadingDevices = false;
        _status = '❌ ${service.lastError}';
        _statusColor = Colors.red;
      });
      return;
    }

    final devices = await service.getDevices();

    setState(() {
      _loadingDevices = false;
      _devices = devices;
      if (devices.isEmpty) {
        _status = '⚠️ В аккаунте нет устройств';
        _statusColor = Colors.orange;
      } else {
        _status = '✅ Найдено устройств: ${devices.length}';
        _statusColor = Colors.green;
      }
    });
  }

  // ===== Шаг 2. Полное подключение с выбранным устройством =====
  Future<void> _connect() async {
    final modbus = Provider.of<ModbusService>(context, listen: false);
    final rtu = Provider.of<ModbusRtuService>(context, listen: false);
    final messenger = ScaffoldMessenger.maybeOf(context);

    // ✅ Гасим только ЛОКАЛЬНЫЕ каналы (TCP/RTU),
    //    Cloud НЕ отключаем — мы как раз к нему подключаемся
    if (modbus.connected) {
      LoggerService().log('🔄 Отключаем TCP перед подключением к Cloud');
      modbus.disconnect();
    }
    if (rtu.connected) {
      LoggerService().log('🔄 Отключаем RTU перед подключением к Cloud');
      await rtu.disconnect();
    }

    final login = _loginCtrl.text.trim();
    final pass = _passCtrl.text;
    final deviceId = int.tryParse(_deviceIdCtrl.text);

    if (login.isEmpty || pass.isEmpty) {
      _setStatus('❌ Введите логин и пароль', Colors.red);
      return;
    }
    if (deviceId == null || deviceId <= 0) {
      _setStatus('❌ Введите ID устройства', Colors.red);
      return;
    }

    setState(() {
      _connecting = true;
      _status = '⏳ Подключение к Owen Cloud...';
      _statusColor = Colors.orange;
    });

    final service = Provider.of<OwenCloudService>(context, listen: false);
    final config = Provider.of<ConfigModel>(context, listen: false);

    final ok = await service.connect(
      login: login,
      password: pass,
      deviceId: deviceId,
      writeGroupId: config.cloudConfig?.writeGroupId ?? 0,
      cachedParamIds: config.cloudConfig?.paramIdCache,
    );

    if (!ok) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('❌ ${service.lastError}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _connecting = false;
        _status = '❌ ${service.lastError}';
        _statusColor = Colors.red;
      });
      return;
    }

    // ✅ ВОТ ЭТА СТРОКА — переключаем активный канал на Cloud
    config.connectionType = 'cloud';

    // Обновим кэш ID параметров
    final paramIdsOk = await service.refreshParamIds();

    setState(() {
      _connecting = false;
      _status = paramIdsOk
          ? '✅ Подключено к Owen Cloud (${service.paramIdCache.length} параметров)'
          : '⚠️ Подключено, но не удалось загрузить параметры';
      _statusColor = paramIdsOk ? Colors.green : Colors.orange;
    });
  }

  // ===== Шаг 3. Сохранение в конфиг =====
  Future<void> _saveToConfig() async {
    final login = _loginCtrl.text.trim();
    final pass = _passCtrl.text;
    final deviceId = int.tryParse(_deviceIdCtrl.text);

    if (login.isEmpty || pass.isEmpty || deviceId == null) {
      _setStatus('❌ Заполните все поля перед сохранением', Colors.red);
      return;
    }

    setState(() {
      _saving = true;
      _status = '⏳ Сохранение...';
      _statusColor = Colors.orange;
    });

    final config = Provider.of<ConfigModel>(context, listen: false);
    final service = Provider.of<OwenCloudService>(context, listen: false);

    config.connectionType = 'cloud';
    config.rtuConfig = null;
    config.cloudConfig = OwenCloudConfig(
      login: login,
      password: pass,
      token: service.token,
      tokenExpiry: DateTime.now().add(const Duration(minutes: 20)),
      deviceId: deviceId,
      deviceName: _selectedDevice?['name']?.toString(),
      paramIdCache: service.paramIdCache,
    );
    try {
      final configService = ConfigService();
      await configService.saveConfig(config);

      final activeName = await ConfigManager.getActiveConfig();
      if (activeName != null) {
        await ConfigManager.saveConfig(config, name: activeName);
      } else {
        final fileName =
            '${config.projectName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.json';
        await ConfigManager.saveConfig(config, name: fileName);
        await ConfigManager.setActiveConfig(fileName);
      }

      setState(() {
        _saving = false;
        _status = '✅ Настройки сохранены в конфиг';
        _statusColor = Colors.green;
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _status = '❌ Ошибка сохранения: $e';
        _statusColor = Colors.red;
      });
      LoggerService().log('❌ Сохранение Owen Cloud: $e', level: LogLevel.error);
    }
  }

  void _setStatus(String msg, Color color) {
    setState(() {
      _status = msg;
      _statusColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Подключение к Owen Cloud'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [Colors.grey[900]!, Colors.grey[800]!]
                : [Colors.grey[50]!, Colors.grey[200]!],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Icon(Icons.cloud_outlined, size: 64, color: Colors.blue[700]),
              const SizedBox(height: 16),
              const Text(
                'Owen Cloud REST API',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Авторизуйтесь в личном кабинете и выберите устройство',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),

              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _loginCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Логин (e-mail)',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _deviceIdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'ID устройства',
                          hintText: 'например, 248007',
                          prefixIcon: Icon(Icons.memory),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Загрузка списка устройств
              OutlinedButton.icon(
                onPressed: _loadingDevices ? null : _loadDevices,
                icon: _loadingDevices
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(
                  _loadingDevices
                      ? 'Загрузка...'
                      : 'Загрузить список устройств',
                ),
              ),

              if (_devices.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: int.tryParse(_deviceIdCtrl.text),
                  decoration: const InputDecoration(
                    labelText: 'Выберите устройство',
                    border: OutlineInputBorder(),
                  ),
                  items: _devices.map((d) {
                    final id = d['id'] is int
                        ? d['id'] as int
                        : int.tryParse(d['id'].toString());
                    final name =
                        d['name']?.toString() ??
                        d['identifier']?.toString() ??
                        'Устройство $id';
                    return DropdownMenuItem<int>(
                      value: id,
                      child: Text('$name (ID $id)'),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _deviceIdCtrl.text = v.toString();
                        _selectedDevice = _devices.firstWhere(
                          (d) =>
                              (d['id'] is int
                                  ? d['id']
                                  : int.tryParse(d['id'].toString())) ==
                              v,
                          orElse: () => <String, dynamic>{},
                        );
                      });
                    }
                  },
                ),
              ],

              const SizedBox(height: 16),

              // Кнопка "Подключиться"
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _connecting ? null : _connect,
                  icon: _connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_done),
                  label: Text(
                    _connecting ? 'Подключение...' : 'Подключиться',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Кнопка "Сохранить"
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveToConfig,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _saving ? 'Сохранение...' : 'Сохранить в конфиг',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Кнопка "Выйти / сменить аккаунт" — с фоном и границей
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Выйти из аккаунта?'),
                        content: const Text(
                          'Логин, пароль и токен будут удалены из конфигурации. '
                          'При следующем запуске потребуется ввести данные заново.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Отмена'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('Выйти'),
                          ),
                        ],
                      ),
                    );

                    if (confirm != true || !mounted) return;

                    final service = Provider.of<OwenCloudService>(
                      context,
                      listen: false,
                    );
                    await service.disconnect();

                    final config = Provider.of<ConfigModel>(
                      context,
                      listen: false,
                    );
                    config.cloudConfig = null;
                    if (config.connectionType == 'cloud') {
                      config.connectionType = 'tcp';
                    }

                    final configService = ConfigService();
                    await configService.saveConfig(config);

                    final activeName = await ConfigManager.getActiveConfig();
                    if (activeName != null) {
                      await ConfigManager.saveConfig(config, name: activeName);
                    }

                    if (mounted) {
                      _loginCtrl.clear();
                      _passCtrl.clear();
                      _deviceIdCtrl.clear();
                      setState(() {
                        _devices = [];
                        _selectedDevice = null;
                        _status = '✅ Вы вышли из аккаунта';
                        _statusColor = Colors.green;
                      });
                    }
                  },
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text(
                    'Выйти / сменить аккаунт',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.06),
                    side: const BorderSide(color: Colors.red, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              if (_status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _statusColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _status,
                    style: TextStyle(
                      color: _statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Токен обновляется автоматически за 4 минуты до истечения. '
                        'ID параметров сопоставляются кодам P<адрес Modbus>.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
