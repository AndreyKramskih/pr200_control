// lib/screens/connection_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:async';
import '../models/config_model.dart';
import '../services/modbus_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadConfig();
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
    _ipController.text = config.modbusServer.ip;
    _portController.text = config.modbusServer.port.toString();
    _slaveController.text = config.modbusServer.slaveId.toString();
    _timeoutController.text = config.modbusServer.timeout.toString();
  }

  @override
  Widget build(BuildContext context) {
    final modbus = Provider.of<ModbusService>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Подключение к оборудованию'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
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
                child: const Icon(
                  Icons.settings_ethernet,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),

              // Заголовок
              Text(
                'Настройки Modbus TCP',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Введите параметры подключения к устройству',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.black54,
                ),
              ),
              const SizedBox(height: 24),

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
                      onPressed: _isTesting || _isConnecting
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
                      onPressed: _isTesting || _isConnecting
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

              // Состояние подключения
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: modbus.connected
                      ? (isDark ? Colors.green[900] : Colors.green[50])
                      : (isDark ? Colors.grey[800] : Colors.grey[50]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: modbus.connected ? Colors.green : Colors.grey,
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
                        color: modbus.connected ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      modbus.connected ? 'Подключено' : 'Отключено',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: modbus.connected ? Colors.green : Colors.red,
                      ),
                    ),
                    if (modbus.connected && modbus.lastError.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      Text(
                        '(${modbus.lastError})',
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
              if (modbus.connected)
                TextButton.icon(
                  onPressed: () {
                    modbus.disconnect();
                    setState(() {
                      _status = 'Отключено';
                      _statusColor = Colors.grey;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Отключено от устройства'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  },
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

  Future<void> _testConnection(BuildContext context) async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text) ?? 502;

    if (ip.isEmpty) {
      setState(() {
        _status = 'Введите IP адрес';
        _statusColor = Colors.orange;
      });
      return;
    }

    setState(() {
      _status = 'Проверка подключения...';
      _statusColor = Colors.orange;
      _isTesting = true;
    });

    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 3),
      );
      socket.close();

      setState(() {
        _status = '✅ Порт $port доступен на $ip';
        _statusColor = Colors.green;
        _isTesting = false;
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Порт $port доступен на $ip'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on SocketException catch (e) {
      setState(() {
        _status = '❌ Ошибка: ${e.message}';
        _statusColor = Colors.red;
        _isTesting = false;
      });
    } on TimeoutException catch (_) {
      setState(() {
        _status = '❌ Таймаут: порт $port не отвечает';
        _statusColor = Colors.red;
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _status = '❌ Ошибка: ${e.toString().substring(0, 80)}';
        _statusColor = Colors.red;
        _isTesting = false;
      });
    }
  }

  Future<void> _connect(BuildContext context) async {
    final modbus = Provider.of<ModbusService>(context, listen: false);
    final config = Provider.of<ConfigModel>(context, listen: false);

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

    config.modbusServer.ip = ip;
    config.modbusServer.port = port;
    config.modbusServer.slaveId = slaveId;
    config.modbusServer.timeout = timeout;

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
      setState(() {
        _status = '✅ Подключено к $ip:$port';
        _statusColor = Colors.green;
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Подключение успешно!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } else {
      setState(() {
        _status = '❌ Ошибка: ${modbus.lastError}';
        _statusColor = Colors.red;
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка подключения: ${modbus.lastError}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
