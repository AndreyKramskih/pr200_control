// lib/screens/connection_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
//import 'dart:io';
import 'dart:async';
import 'package:flutter_serial_communication/models/device_info.dart';
import '../models/config_model.dart';
import '../services/modbus_service.dart';
import '../services/modbus_rtu_service.dart';
import '../services/config_service.dart';
import '../services/logger_service.dart';
import '../services/config_manager.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _slaveController = TextEditingController();
  final TextEditingController _timeoutController = TextEditingController();

  String _status = '';
  Color _statusColor = Colors.grey;
  bool _isTesting = false;
  bool _isConnecting = false;
  bool _isSaving = false;

  // RTU переменные
  String _connectionType = 'tcp'; // 'tcp' или 'rtu'
  List<DeviceInfo> _usbDevices = [];
  DeviceInfo? _selectedDevice;
  bool _isLoadingDevices = false;
  int _baudRate = 115200;
  final List<int> _baudRates = [
    1200,
    2400,
    4800,
    9600,
    19200,
    38400,
    57600,
    115200,
  ];

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _scanUsbDevices();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _slaveController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  void _loadConfig() {
    final config = Provider.of<ConfigModel>(context, listen: false);

    // TCP настройки
    _ipController.text = config.modbusServer.ip;
    _portController.text = config.modbusServer.port.toString();
    _slaveController.text = config.modbusServer.slaveId.toString();
    _timeoutController.text = config.modbusServer.timeout.toString();

    // ✅ Загружаем тип подключения
    _connectionType = config.connectionType;

    // ✅ Загружаем RTU настройки
    if (config.rtuConfig != null) {
      _baudRate = config.rtuConfig!.baudRate;
    }
  }

  Future<void> _scanUsbDevices() async {
    setState(() {
      _isLoadingDevices = true;
      _usbDevices = [];
      _selectedDevice = null;
    });

    try {
      final rtuService = Provider.of<ModbusRtuService>(context, listen: false);
      final devices = await rtuService.getAvailableDevices();
      setState(() {
        _usbDevices = devices;
        _isLoadingDevices = false;
        if (devices.isNotEmpty) {
          _selectedDevice = devices.first;
        }
      });
      LoggerService().log('🔍 Найдено ${devices.length} USB устройств');
    } catch (e) {
      setState(() {
        _isLoadingDevices = false;
      });
      LoggerService().log(
        '❌ Ошибка сканирования USB: $e',
        level: LogLevel.error,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сканирования USB: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveToConfig(BuildContext context) async {
    final config = Provider.of<ConfigModel>(context, listen: false);

    if (_connectionType == 'tcp') {
      final ip = _ipController.text.trim();
      final port = int.tryParse(_portController.text) ?? 502;
      final slaveId = int.tryParse(_slaveController.text) ?? 1;
      final timeout = int.tryParse(_timeoutController.text) ?? 3;

      if (ip.isEmpty) {
        setState(() {
          _status = 'Введите IP адрес';
          _statusColor = Colors.orange;
        });
        return;
      }

      setState(() {
        _status = 'Сохранение...';
        _statusColor = Colors.orange;
        _isSaving = true;
      });

      try {
        config.modbusServer.ip = ip;
        config.modbusServer.port = port;
        config.modbusServer.slaveId = slaveId;
        config.modbusServer.timeout = timeout;

        config.connectionType = 'tcp';
        config.rtuConfig = null;

        final configService = ConfigService();
        await configService.saveConfig(config);

        // ✅ СОХРАНЯЕМ В АКТИВНЫЙ КОНФИГ
        await _saveToActiveConfig(config);

        setState(() {
          _status = '✅ Настройки сохранены';
          _statusColor = Colors.green;
          _isSaving = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Настройки сохранены'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        LoggerService().log('✅ Настройки сохранены (TCP)');
      } catch (e) {
        setState(() {
          _status = '❌ Ошибка сохранения: $e';
          _statusColor = Colors.red;
          _isSaving = false;
        });
        LoggerService().log('❌ Ошибка сохранения: $e', level: LogLevel.error);
      }
    } else {
      // RTU
      if (_selectedDevice == null) {
        setState(() {
          _status = '❌ Выберите USB устройство';
          _statusColor = Colors.orange;
        });
        return;
      }

      final slaveId = int.tryParse(_slaveController.text) ?? 1;
      final timeout = int.tryParse(_timeoutController.text) ?? 3;

      setState(() {
        _status = 'Сохранение RTU...';
        _statusColor = Colors.orange;
        _isSaving = true;
      });

      try {
        config.modbusServer.slaveId = slaveId;
        config.modbusServer.timeout = timeout;

        config.connectionType = 'rtu';
        config.rtuConfig = RtuConfig(
          port: _selectedDevice!.deviceName,
          baudRate: _baudRate,
          dataBits: 8,
          stopBits: 1,
          parity: 'none',
        );

        final configService = ConfigService();
        await configService.saveConfig(config);

        // ✅ СОХРАНЯЕМ В АКТИВНЫЙ КОНФИГ
        await _saveToActiveConfig(config);

        setState(() {
          _status = '✅ RTU настройки сохранены';
          _statusColor = Colors.green;
          _isSaving = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ RTU настройки сохранены'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        LoggerService().log('✅ RTU настройки сохранены');
      } catch (e) {
        setState(() {
          _status = '❌ Ошибка сохранения: $e';
          _statusColor = Colors.red;
          _isSaving = false;
        });
        LoggerService().log(
          '❌ Ошибка сохранения RTU: $e',
          level: LogLevel.error,
        );
      }
    }
  }

  // ✅ НОВЫЙ МЕТОД ДЛЯ СОХРАНЕНИЯ В АКТИВНЫЙ КОНФИГ
  Future<void> _saveToActiveConfig(ConfigModel config) async {
    try {
      final activeConfigName = await ConfigManager.getActiveConfig();
      if (activeConfigName != null) {
        // Обновляем существующий активный конфиг
        await ConfigManager.saveConfig(config, name: activeConfigName);
        LoggerService().log('✅ Активный конфиг обновлен: $activeConfigName');
      } else {
        // Если нет активного — создаем новый
        final projectName = config.projectName.replaceAll(' ', '_');
        final fileName =
            '${projectName}_${DateTime.now().millisecondsSinceEpoch}.json';
        await ConfigManager.saveConfig(config, name: fileName);
        await ConfigManager.setActiveConfig(fileName);
        LoggerService().log('✅ Создан новый активный конфиг: $fileName');
      }
    } catch (e) {
      LoggerService().log(
        '❌ Ошибка сохранения в активный конфиг: $e',
        level: LogLevel.error,
      );
    }
  }
  // lib/screens/connection_screen.dart

  Future<void> _connect(BuildContext context) async {
    final modbus = Provider.of<ModbusService>(context, listen: false);
    final rtuService = Provider.of<ModbusRtuService>(context, listen: false);

    if (_connectionType == 'tcp') {
      final ip = _ipController.text.trim();
      final port = int.tryParse(_portController.text) ?? 502;
      final slaveId = int.tryParse(_slaveController.text) ?? 1;
      final timeout = int.tryParse(_timeoutController.text) ?? 3;

      if (ip.isEmpty) {
        setState(() {
          _status = 'Введите IP адрес';
          _statusColor = Colors.orange;
        });
        return;
      }

      setState(() {
        _status = 'Подключение...';
        _statusColor = Colors.orange;
        _isConnecting = true;
      });

      // ✅ Если RTU подключен — отключаем его
      if (rtuService.connected) {
        LoggerService().log('🔄 Отключаем RTU перед подключением TCP');
        await rtuService.disconnect();
      }

      final success = await modbus.connect(
        ip,
        port: port,
        slaveId: slaveId,
        timeout: timeout,
      );

      setState(() {
        _isConnecting = false;
      });

      if (success) {
        final config = Provider.of<ConfigModel>(context, listen: false);
        config.connectionType = 'tcp';

        setState(() {
          _status = '✅ Подключено к $ip:$port';
          _statusColor = Colors.green;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Подключение успешно!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _status = '❌ Ошибка: ${modbus.lastError}';
          _statusColor = Colors.red;
        });
      }
    } else {
      // RTU
      if (_selectedDevice == null) {
        setState(() {
          _status = '❌ Выберите USB устройство';
          _statusColor = Colors.orange;
        });
        return;
      }

      final slaveId = int.tryParse(_slaveController.text) ?? 1;
      final timeout = int.tryParse(_timeoutController.text) ?? 3;
      final String devicePath = _selectedDevice!.deviceName;

      setState(() {
        _status = 'Подключение RTU...';
        _statusColor = Colors.orange;
        _isConnecting = true;
      });

      // ✅ Если TCP подключен — отключаем его
      if (modbus.connected) {
        LoggerService().log('🔄 Отключаем TCP перед подключением RTU');
        modbus.disconnect();
      }

      final success = await rtuService.connect(
        port: devicePath,
        slaveId: slaveId,
        timeout: timeout,
        baudRate: _baudRate,
      );

      setState(() {
        _isConnecting = false;
      });

      if (success) {
        final config = Provider.of<ConfigModel>(context, listen: false);
        config.connectionType = 'rtu';

        setState(() {
          _status = '✅ RTU подключен к $devicePath';
          _statusColor = Colors.green;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('RTU подключен!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        LoggerService().log('✅ RTU подключен к $devicePath');
      } else {
        setState(() {
          _status = '❌ Ошибка RTU: ${rtuService.lastError}';
          _statusColor = Colors.red;
        });
        LoggerService().log(
          '❌ Ошибка RTU: ${rtuService.lastError}',
          level: LogLevel.error,
        );
      }
    }
  }

  Future<void> _testConnection(BuildContext context) async {
    if (_connectionType == 'tcp') {
      // ... существующий код без изменений ...
    } else {
      // RTU тест
      final rtuService = Provider.of<ModbusRtuService>(context, listen: false);
      final modbus = Provider.of<ModbusService>(context, listen: false);

      if (_selectedDevice == null) {
        setState(() {
          _status = '❌ Выберите USB устройство';
          _statusColor = Colors.orange;
        });
        return;
      }

      setState(() {
        _status = 'Проверка RTU...';
        _statusColor = Colors.orange;
        _isTesting = true;
      });

      try {
        // ✅ Если TCP подключен — отключаем его для теста
        if (modbus.connected) {
          LoggerService().log('🔄 Отключаем TCP перед тестом RTU');
          modbus.disconnect();
        }

        final String devicePath = _selectedDevice!.deviceName;
        final success = await rtuService.connect(
          port: devicePath,
          slaveId: int.tryParse(_slaveController.text) ?? 1,
          timeout: 2,
          baudRate: _baudRate,
        );

        setState(() {
          _isTesting = false;
          if (success) {
            _status = '✅ RTU устройство $devicePath доступно';
            _statusColor = Colors.green;
            rtuService.disconnect();
          } else {
            _status = '❌ RTU устройство не отвечает';
            _statusColor = Colors.red;
          }
        });
        LoggerService().log('RTU тест: $success');
      } catch (e) {
        setState(() {
          _isTesting = false;
          _status = '❌ Ошибка: ${e.toString().substring(0, 80)}';
          _statusColor = Colors.red;
        });
        LoggerService().log('❌ RTU тест ошибка: $e', level: LogLevel.error);
      }
    }
  }

  Future<void> _disconnect() async {
    if (_connectionType == 'tcp') {
      final modbus = Provider.of<ModbusService>(context, listen: false);
      modbus.disconnect();
    } else {
      final rtuService = Provider.of<ModbusRtuService>(context, listen: false);
      await rtuService.disconnect();
    }

    setState(() {
      _status = 'Отключено';
      _statusColor = Colors.grey;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Отключено'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    LoggerService().log('🔌 Отключено');
  }

  Widget _buildConnectionTypeSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? Colors.grey[850] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Тип подключения',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('TCP/IP'),
                    value: 'tcp',
                    groupValue: _connectionType,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) {
                      setState(() => _connectionType = v!);
                      _scanUsbDevices();
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('RTU (USB)'),
                    value: 'rtu',
                    groupValue: _connectionType,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) {
                      setState(() => _connectionType = v!);
                      _scanUsbDevices();
                    },
                  ),
                ),
              ],
            ),
            if (_connectionType == 'rtu') ...[
              const Divider(),
              _buildRtuControls(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRtuControls() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Параметры USB',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),

        // Выбор USB устройства
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<DeviceInfo>(
            value: _selectedDevice,
            isExpanded: true,
            hint: Text(
              'Выберите USB устройство',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            dropdownColor: isDark ? Colors.grey[800] : Colors.white,
            items: [
              if (_usbDevices.isEmpty && !_isLoadingDevices)
                const DropdownMenuItem<DeviceInfo>(
                  value: null,
                  child: Text('Нет устройств'),
                ),
              ..._usbDevices.map((device) {
                return DropdownMenuItem<DeviceInfo>(
                  value: device,
                  child: Text(
                    device.deviceName,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
            onChanged: (device) {
              setState(() {
                _selectedDevice = device;
              });
            },
          ),
        ),

        const SizedBox(height: 8),

        // Кнопка обновления и статус
        Row(
          children: [
            IconButton(
              icon: _isLoadingDevices
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _scanUsbDevices,
              tooltip: 'Обновить список устройств',
            ),
            Text(
              _isLoadingDevices ? 'Поиск устройств...' : 'Обновить',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const Spacer(),
            if (_usbDevices.isNotEmpty)
              Text(
                '${_usbDevices.length} устройств',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
          ],
        ),

        if (_usbDevices.isEmpty && !_isLoadingDevices)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '⚠️ USB устройства не найдены. Подключите кабель и нажмите обновить.',
              style: TextStyle(fontSize: 12, color: Colors.orange[700]),
            ),
          ),

        const SizedBox(height: 8),

        // Выбор скорости
        DropdownButtonFormField<int>(
          decoration: InputDecoration(
            labelText: 'Скорость (bps)',
            labelStyle: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            filled: true,
            fillColor: isDark ? Colors.grey[800] : Colors.white,
          ),
          dropdownColor: isDark ? Colors.grey[800] : Colors.white,
          value: _baudRate,
          items: _baudRates.map((rate) {
            return DropdownMenuItem<int>(
              value: rate,
              child: Text(rate.toString()),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _baudRate = value ?? 9600;
            });
          },
        ),

        const SizedBox(height: 8),

        // Подсказка
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Для ПР200 используйте скорость 115200 и адрес 16',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final modbus = Provider.of<ModbusService>(context);
    final rtuService = Provider.of<ModbusRtuService>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isConnected = _connectionType == 'tcp'
        ? modbus.connected
        : rtuService.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Подключение к оборудованию'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isSaving ? null : () => _saveToConfig(context),
            tooltip: 'Сохранить настройки в конфигурацию',
          ),
        ],
      ),
      body: Container(
        padding: const EdgeInsets.all(24),
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
          child: Column(
            children: [
              // Иконка
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue[700],
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  _connectionType == 'tcp'
                      ? Icons.settings_ethernet
                      : Icons.usb,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),

              // Заголовок
              Text(
                _connectionType == 'tcp'
                    ? 'Настройки Modbus TCP'
                    : 'Настройки Modbus RTU (USB)',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _connectionType == 'tcp'
                    ? 'Введите параметры подключения к устройству'
                    : 'Подключите USB-кабель к устройству',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.black54,
                ),
              ),
              const SizedBox(height: 24),

              // Переключатель типа подключения
              _buildConnectionTypeSelector(),

              // Форма
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: isDark ? Colors.grey[850] : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      if (_connectionType == 'tcp') ...[
                        _buildTextField(
                          controller: _ipController,
                          label: 'IP адрес',
                          icon: Icons.network_wifi,
                          hint: '192.168.1.100',
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _portController,
                          label: 'Порт',
                          icon: Icons.settings_input_component,
                          hint: '502',
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildTextField(
                        controller: _slaveController,
                        label: 'Slave ID',
                        icon: Icons.numbers,
                        hint: '1',
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _timeoutController,
                        label: 'Таймаут (сек)',
                        icon: Icons.timer,
                        hint: '3',
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Статус
              if (_status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _statusColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _status,
                          style: TextStyle(
                            color: _statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // Кнопки
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isTesting || _isConnecting || _isSaving
                          ? null
                          : () => _testConnection(context),
                      icon: _isTesting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.network_check),
                      label: Text(_isTesting ? 'Проверка...' : 'Тест связи'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: Colors.blue[300],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isTesting || _isConnecting || _isSaving
                          ? null
                          : () => _connect(context),
                      icon: _isConnecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle),
                      label: Text(
                        _isConnecting ? 'Подключение...' : 'Подключиться',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: Colors.green[300],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Кнопка сохранения
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isTesting || _isConnecting || _isSaving
                      ? null
                      : () => _saveToConfig(context),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _isSaving ? 'Сохранение...' : 'Сохранить в конфигурацию',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: Colors.orange[300],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Состояние подключения
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isConnected
                      ? (isDark ? Colors.green[900] : Colors.green[50])
                      : (isDark ? Colors.grey[800] : Colors.grey[50]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isConnected ? Colors.green : Colors.grey,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isConnected ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isConnected ? 'Подключено' : 'Отключено',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isConnected ? Colors.green : Colors.red,
                      ),
                    ),
                    if (isConnected) ...[
                      const SizedBox(width: 16),
                      Text(
                        _connectionType == 'tcp'
                            ? '${modbus.ip}:${modbus.port}'
                            : rtuService.portName,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Кнопка отключения
              if (isConnected)
                TextButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.link_off, color: Colors.red),
                  label: const Text(
                    'Отключиться',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
        fontSize: 18,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Colors.grey[500] : Colors.grey[600],
        ),
        prefixIcon: Icon(
          icon,
          color: isDark ? Colors.white70 : Colors.blue[700],
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        filled: true,
        fillColor: isDark ? Colors.grey[800] : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
